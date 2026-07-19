// Utility to extract chapter information from audio files using ffprobe
// and from Audible metadata.json files
import { execFile } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import fs from 'fs/promises';

const execFileAsync = promisify(execFile);

// ffprobe runs inside request handlers (lazy chapter extraction). Use execFile
// with an argument array — no shell, so the file path can't break out of a
// quoted string (SEC-4) — and cap it so a pathological/huge file can't hang the
// handler indefinitely.
const FFPROBE_TIMEOUT_MS = 30_000;

export interface Chapter {
  chapterNumber: number;
  title: string;
  startTime: number; // in seconds
  endTime: number; // in seconds
  duration: number; // in seconds
}

interface FFProbeChapter {
  id: number;
  start_time: string;
  end_time: string;
  tags?: {
    title?: string;
  };
}

interface FFProbeFormat {
  duration?: string;
  bit_rate?: string;
  format_name?: string;
  tags?: {
    CUESHEET?: string;
    title?: string;
    artist?: string;
    album?: string;
    composer?: string;
    publisher?: string;
    date?: string;
    SERIES?: string;
    PART?: string;
    [key: string]: any;
  };
}

interface FFProbeOutput {
  chapters?: FFProbeChapter[];
  format?: FFProbeFormat;
}

/**
 * Parse cuesheet format to extract chapter titles
 * Format: TRACK N AUDIO\n  TITLE "Chapter Title"\n  INDEX 01 MM:SS:FF
 */
function parseCuesheet(cuesheet: string): Map<number, string> {
  const chapterTitles = new Map<number, string>();

  if (!cuesheet) return chapterTitles;

  // Split by TRACK entries
  const trackRegex = /TRACK\s+(\d+)\s+AUDIO\s+TITLE\s+"([^"]+)"/g;
  let match;

  while ((match = trackRegex.exec(cuesheet)) !== null) {
    const trackNumber = parseInt(match[1], 10);
    const title = match[2];
    // FFProbe chapters are 0-based, cuesheet tracks are 1-based
    chapterTitles.set(trackNumber - 1, title);
  }

  return chapterTitles;
}

/**
 * Extract chapters from an audio file using ffprobe
 * @param audioFilePath Absolute path to the audio file
 * @returns Array of chapters with titles and timestamps
 */
export async function extractChapters(audioFilePath: string): Promise<Chapter[]> {
  try {
    // Run ffprobe to extract chapters and format metadata. execFile passes the
    // path as a literal argv entry — no shell interpolation, no escaping needed.
    const { stdout } = await execFileAsync(
      'ffprobe',
      ['-v', 'quiet', '-print_format', 'json', '-show_chapters', '-show_format', audioFilePath],
      { timeout: FFPROBE_TIMEOUT_MS }
    );

    const data: FFProbeOutput = JSON.parse(stdout);

    if (!data.chapters || data.chapters.length === 0) {
      return [];
    }

    // Try to get better chapter titles from cuesheet
    const cuesheet = data.format?.tags?.CUESHEET;
    const chapterTitles = cuesheet ? parseCuesheet(cuesheet) : new Map<number, string>();

    // Convert ffprobe chapters to our Chapter format
    const chapters: Chapter[] = data.chapters.map((ch, index) => {
      const startTime = parseFloat(ch.start_time);
      const endTime = parseFloat(ch.end_time);
      const duration = endTime - startTime;

      // Prefer cuesheet title, fallback to chapter tag title or generic title
      let title = chapterTitles.get(ch.id);
      if (!title) {
        title = ch.tags?.title || `Chapter ${index + 1}`;
      }

      return {
        chapterNumber: index + 1, // 1-based for display
        title,
        startTime,
        endTime,
        duration,
      };
    });

    return chapters;
  } catch (error) {
    console.error('Error extracting chapters:', error);
    throw new Error(
      `Failed to extract chapters: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

/**
 * Extract basic audio metadata from a file
 * @param audioFilePath Absolute path to the audio file
 * @returns Audio metadata including duration, bitrate, etc.
 */
export async function extractAudioMetadata(audioFilePath: string): Promise<{
  duration: number;
  bitrate: number;
  format: string;
  title?: string;
  artist?: string;
  album?: string;
  narrator?: string;
  publisher?: string;
  releaseDate?: string;
  series?: string;
  seriesPart?: string;
}> {
  try {
    const { stdout } = await execFileAsync(
      'ffprobe',
      ['-v', 'quiet', '-print_format', 'json', '-show_format', audioFilePath],
      { timeout: FFPROBE_TIMEOUT_MS }
    );

    const data: FFProbeOutput = JSON.parse(stdout);

    if (!data.format) {
      throw new Error('No format information found');
    }

    const format = data.format;
    const tags = format.tags || {};

    return {
      duration: parseFloat(format.duration || '0'),
      bitrate: parseInt(format.bit_rate || '0', 10),
      format: format.format_name || 'unknown',
      title: tags.title,
      artist: tags.artist,
      album: tags.album,
      narrator: tags.composer, // Audible stores narrator in composer tag
      publisher: tags.publisher,
      releaseDate: tags.date,
      series: tags.SERIES,
      seriesPart: tags.PART,
    };
  } catch (error) {
    console.error('Error extracting audio metadata:', error);
    throw new Error(
      `Failed to extract metadata: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

/**
 * Check if ffprobe is available on the system
 */
export async function isFFProbeAvailable(): Promise<boolean> {
  try {
    await execFileAsync('which', ['ffprobe'], { timeout: FFPROBE_TIMEOUT_MS });
    return true;
  } catch {
    return false;
  }
}

/**
 * Audible ChapterInfo structure from metadata.json
 */
interface AudibleChapterInfo {
  brandIntroDurationMs: number;
  brandOutroDurationMs: number;
  chapters: Array<{
    title: string;
    start_offset_ms: number;
    start_offset_sec: number;
    length_ms: number;
  }>;
  runtime_length_ms: number;
  runtime_length_sec: number;
  is_accurate: boolean;
}

interface AudibleMetadata {
  ChapterInfo?: AudibleChapterInfo;
  asin?: string;
  title?: string;
}

/**
 * Extract chapters from Audible metadata.json file
 * This is more accurate than ffprobe extraction because it uses the original
 * Audible chapter data, adjusted for the brand intro that Libation strips.
 *
 * @param metadataJsonPath Absolute path to the .metadata.json file
 * @returns Array of chapters with titles and timestamps, or null if not available
 */
export async function extractChaptersFromAudibleMetadata(
  metadataJsonPath: string
): Promise<Chapter[] | null> {
  try {
    const content = await fs.readFile(metadataJsonPath, 'utf-8');
    const metadata: AudibleMetadata = JSON.parse(content);

    if (!metadata.ChapterInfo?.chapters || metadata.ChapterInfo.chapters.length === 0) {
      return null;
    }

    const chapterInfo = metadata.ChapterInfo;
    const brandIntroSeconds = chapterInfo.brandIntroDurationMs / 1000;

    // Convert Audible chapters to our Chapter format
    // Subtract the brand intro duration since Libation strips it from the MP3
    const chapters: Chapter[] = chapterInfo.chapters.map((ch, index) => {
      // Audible times include the brand intro, but Libation strips it
      // So we need to subtract brandIntroDurationMs from each timestamp
      const startTime = Math.max(0, ch.start_offset_ms / 1000 - brandIntroSeconds);
      const duration = ch.length_ms / 1000;
      const endTime = startTime + duration;

      return {
        chapterNumber: index + 1, // 1-based for display
        title: ch.title,
        startTime,
        endTime,
        duration,
      };
    });

    return chapters;
  } catch (error) {
    // File doesn't exist or is invalid - fall back to ffprobe
    console.warn('Could not read Audible metadata:', error);
    return null;
  }
}

/**
 * Find the metadata.json file for a given audio file
 * Libation creates metadata files with the pattern: "BookTitle [ASIN].metadata.json"
 *
 * @param audioFilePath Path to the audio file (e.g., /path/to/Book [ASIN].mp3)
 * @returns Path to the metadata.json file, or null if not found
 */
export async function findAudibleMetadataFile(audioFilePath: string): Promise<string | null> {
  try {
    const dir = path.dirname(audioFilePath);
    const files = await fs.readdir(dir);

    // Look for .metadata.json file in the same directory
    const metadataFile = files.find((f) => f.endsWith('.metadata.json'));

    if (metadataFile) {
      return path.join(dir, metadataFile);
    }

    return null;
  } catch {
    return null;
  }
}

/**
 * Find the CUE file for a given audio file
 * Libation creates CUE files with the pattern: "BookTitle [ASIN].cue"
 *
 * @param audioFilePath Path to the audio file (e.g., /path/to/Book [ASIN].m4b)
 * @returns Path to the CUE file, or null if not found
 */
export async function findCueFile(audioFilePath: string): Promise<string | null> {
  try {
    const dir = path.dirname(audioFilePath);
    const files = await fs.readdir(dir);

    // Look for .cue file in the same directory
    const cueFile = files.find((f) => f.endsWith('.cue'));

    if (cueFile) {
      return path.join(dir, cueFile);
    }

    return null;
  } catch {
    return null;
  }
}

/**
 * Extract chapters from a CUE file
 * CUE format: TRACK N AUDIO, TITLE "Chapter Title", INDEX 01 MM:SS:FF
 * where FF is frames (75 frames per second)
 *
 * @param cueFilePath Absolute path to the .cue file
 * @param audioDurationSeconds Total duration of audio file (for calculating last chapter end time)
 * @returns Array of chapters with titles and timestamps, or null if not available
 */
export async function extractChaptersFromCueFile(
  cueFilePath: string,
  audioDurationSeconds?: number
): Promise<Chapter[] | null> {
  try {
    const content = await fs.readFile(cueFilePath, 'utf-8');

    const chapters: { title: string; startTime: number }[] = [];
    const trackRegex =
      /TRACK\s+(\d+)\s+AUDIO\s+TITLE\s+"([^"]+)"\s+INDEX\s+01\s+(\d+):(\d+):(\d+)/g;
    let match;

    while ((match = trackRegex.exec(content)) !== null) {
      const minutes = parseInt(match[3], 10);
      const seconds = parseInt(match[4], 10);
      const frames = parseInt(match[5], 10);
      // CUE format uses 75 frames per second
      const startTime = minutes * 60 + seconds + frames / 75;
      chapters.push({ title: match[2], startTime });
    }

    if (chapters.length === 0) {
      return null;
    }

    // Convert to Chapter format with end times
    return chapters.map((ch, index) => {
      const startTime = ch.startTime;
      // End time is start of next chapter, or audio duration for last chapter
      const endTime =
        index < chapters.length - 1
          ? chapters[index + 1].startTime
          : audioDurationSeconds || startTime + 300; // Default 5 min if unknown
      const duration = endTime - startTime;

      return {
        chapterNumber: index + 1,
        title: ch.title,
        startTime,
        endTime,
        duration,
      };
    });
  } catch (error) {
    console.warn('Could not read CUE file:', error);
    return null;
  }
}

/**
 * Extract chapters using the best available method:
 * Priority order (based on accuracy verification of 698 audiobooks):
 * 1. M4B embedded chapters via ffprobe (most accurate, 100% availability)
 * 2. CUE file (97% match M4B within 0.01s tolerance)
 * 3. Audible metadata.json (less granular, fewer chapters)
 *
 * @param audioFilePath Absolute path to the audio file
 * @returns Array of chapters with titles and timestamps
 */
export async function extractChaptersBestMethod(audioFilePath: string): Promise<Chapter[]> {
  // 1. Try ffprobe extraction from M4B/audio file (most accurate)
  try {
    const ffprobeChapters = await extractChapters(audioFilePath);
    if (ffprobeChapters && ffprobeChapters.length > 0) {
      return ffprobeChapters;
    }
  } catch {
    // ffprobe failed or not available, continue to fallbacks
  }

  // 2. Try CUE file (nearly identical to M4B, good fallback)
  const cuePath = await findCueFile(audioFilePath);
  if (cuePath) {
    // Get audio duration for calculating last chapter end time
    let audioDuration: number | undefined;
    try {
      const metadata = await extractAudioMetadata(audioFilePath);
      audioDuration = metadata.duration;
    } catch {
      // Ignore, will use default duration
    }

    const cueChapters = await extractChaptersFromCueFile(cuePath, audioDuration);
    if (cueChapters && cueChapters.length > 0) {
      return cueChapters;
    }
  }

  // 3. Fall back to Audible metadata.json (less granular)
  const metadataPath = await findAudibleMetadataFile(audioFilePath);
  if (metadataPath) {
    const audibleChapters = await extractChaptersFromAudibleMetadata(metadataPath);
    if (audibleChapters && audibleChapters.length > 0) {
      return audibleChapters;
    }
  }

  // No chapters found from any source
  return [];
}

// Utility to extract chapter information from audio files using ffprobe
// and from Audible metadata.json files
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import fs from 'fs/promises';

const execAsync = promisify(exec);

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
    // Escape quotes in file path for shell command
    const escapedPath = audioFilePath.replace(/"/g, '\\"');

    // Run ffprobe to extract chapters and format metadata
    const { stdout } = await execAsync(
      `ffprobe -v quiet -print_format json -show_chapters -show_format "${escapedPath}"`
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
    const escapedPath = audioFilePath.replace(/"/g, '\\"');

    const { stdout } = await execAsync(
      `ffprobe -v quiet -print_format json -show_format "${escapedPath}"`
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
    await execAsync('which ffprobe');
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
 * Extract chapters using the best available method:
 * 1. Try Audible metadata.json first (most accurate)
 * 2. Fall back to ffprobe extraction
 *
 * @param audioFilePath Absolute path to the audio file
 * @returns Array of chapters with titles and timestamps
 */
export async function extractChaptersBestMethod(audioFilePath: string): Promise<Chapter[]> {
  // First, try to find and use Audible metadata
  const metadataPath = await findAudibleMetadataFile(audioFilePath);

  if (metadataPath) {
    const audibleChapters = await extractChaptersFromAudibleMetadata(metadataPath);
    if (audibleChapters && audibleChapters.length > 0) {
      console.log('Using Audible metadata for chapter extraction');
      return audibleChapters;
    }
  }

  // Fall back to ffprobe extraction
  console.log('Falling back to ffprobe for chapter extraction');
  return extractChapters(audioFilePath);
}

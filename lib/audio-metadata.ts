// Utility to extract chapter information from audio files using ffprobe
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';

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

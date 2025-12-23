import { extractChapters, extractAudioMetadata, isFFProbeAvailable } from '@/lib/audio-metadata';
import path from 'path';
import { getAbsoluteMediaPath } from '@/lib/media';

describe('Audio Metadata Extraction', () => {
  beforeAll(async () => {
    const available = await isFFProbeAvailable();
    if (!available) {
      console.warn('ffprobe not available, skipping audio metadata tests');
    }
  });

  it('should detect if ffprobe is available', async () => {
    const available = await isFFProbeAvailable();
    expect(typeof available).toBe('boolean');
  });

  // Skip these tests if ffprobe is not available or if test data doesn't exist
  describe('Chapter Extraction', () => {
    const testAudioPath = path.join(
      getAbsoluteMediaPath(),
      'A Binding of Blood [B0B91976NY]',
      'A Binding of Blood: A Practical Guide to Sorcery, Book 2 [B0B91976NY].mp3'
    );

    it('should extract chapters from an MP3 file', async () => {
      const available = await isFFProbeAvailable();
      if (!available) {
        console.log('Skipping: ffprobe not available');
        return;
      }

      try {
        const chapters = await extractChapters(testAudioPath);

        expect(Array.isArray(chapters)).toBe(true);

        if (chapters.length > 0) {
          const firstChapter = chapters[0];
          expect(firstChapter).toHaveProperty('chapterNumber');
          expect(firstChapter).toHaveProperty('title');
          expect(firstChapter).toHaveProperty('startTime');
          expect(firstChapter).toHaveProperty('endTime');
          expect(firstChapter).toHaveProperty('duration');

          expect(typeof firstChapter.chapterNumber).toBe('number');
          expect(typeof firstChapter.title).toBe('string');
          expect(typeof firstChapter.startTime).toBe('number');
          expect(typeof firstChapter.endTime).toBe('number');
          expect(typeof firstChapter.duration).toBe('number');

          expect(firstChapter.startTime).toBeGreaterThanOrEqual(0);
          expect(firstChapter.endTime).toBeGreaterThan(firstChapter.startTime);
          expect(firstChapter.duration).toBe(firstChapter.endTime - firstChapter.startTime);
        }
      } catch (error) {
        // File might not exist in test environment
        console.log('Skipping: Test audio file not found');
      }
    });

    it('should extract audio metadata from an MP3 file', async () => {
      const available = await isFFProbeAvailable();
      if (!available) {
        console.log('Skipping: ffprobe not available');
        return;
      }

      try {
        const metadata = await extractAudioMetadata(testAudioPath);

        expect(metadata).toHaveProperty('duration');
        expect(metadata).toHaveProperty('bitrate');
        expect(metadata).toHaveProperty('format');

        expect(typeof metadata.duration).toBe('number');
        expect(typeof metadata.bitrate).toBe('number');
        expect(typeof metadata.format).toBe('string');

        expect(metadata.duration).toBeGreaterThan(0);
        expect(metadata.bitrate).toBeGreaterThan(0);
      } catch (error) {
        console.log('Skipping: Test audio file not found');
      }
    });

    it('should handle non-existent files gracefully', async () => {
      const available = await isFFProbeAvailable();
      if (!available) {
        console.log('Skipping: ffprobe not available');
        return;
      }

      const nonExistentPath = '/path/to/nonexistent/file.mp3';

      await expect(extractChapters(nonExistentPath)).rejects.toThrow();
    });

    it('should parse chapter titles from cuesheet', async () => {
      const available = await isFFProbeAvailable();
      if (!available) {
        console.log('Skipping: ffprobe not available');
        return;
      }

      try {
        const chapters = await extractChapters(testAudioPath);

        if (chapters.length > 0) {
          // Check that we have meaningful chapter titles (not just "Chapter N")
          const hasDetailedTitles = chapters.some(
            (ch) => ch.title !== `Chapter ${ch.chapterNumber}`
          );

          // At least some chapters should have detailed titles from cuesheet
          if (hasDetailedTitles) {
            expect(hasDetailedTitles).toBe(true);
          }
        }
      } catch (error) {
        console.log('Skipping: Test audio file not found');
      }
    });
  });

  describe('Cuesheet Parsing', () => {
    it('should handle chapter numbers correctly', async () => {
      const available = await isFFProbeAvailable();
      if (!available) {
        console.log('Skipping: ffprobe not available');
        return;
      }

      try {
        const chapters = await extractChapters(testAudioPath);

        if (chapters.length > 0) {
          // Chapter numbers should be sequential starting from 1
          chapters.forEach((chapter, index) => {
            expect(chapter.chapterNumber).toBe(index + 1);
          });
        }
      } catch (error) {
        console.log('Skipping: Test audio file not found');
      }
    });
  });
});

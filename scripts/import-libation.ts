import 'dotenv/config';
import fs from 'fs/promises';
import path from 'path';
import { prisma } from '@/lib/db';
import { seedTestUser } from './seed-test-user';
import {
  extractChapters,
  findCueFile,
  extractChaptersFromCueFile,
  extractChaptersFromAudibleMetadata,
  extractAudioMetadata,
} from '@/lib/audio-metadata';

// Use LIBATION_PATH from env, or fall back to MEDIA_DATA_PATH, or default to test-data
const LIBATION_PATH =
  process.env.LIBATION_PATH || process.env.MEDIA_DATA_PATH || path.join(process.cwd(), 'test-data');

interface LibationMetadata {
  asin: string;
  title: string;
  authors: Array<{ name: string; asin?: string }>;
  narrators: Array<{ name: string; asin?: string }>;
  series: Array<{ title: string; sequence?: string; asin?: string }>;
  publisher_summary?: string;
  category_ladders?: Array<{
    root: string;
    ladder: Array<{ id: string; name: string }>;
  }>;
  runtime_length_min?: number;
  release_date?: string;
  publisher?: string;
}

export async function importBooks() {
  console.log(`📚 Scanning directory: ${LIBATION_PATH}\n`);

  try {
    const entries = await fs.readdir(LIBATION_PATH, { withFileTypes: true });
    const folders = entries.filter((entry) => entry.isDirectory());

    console.log(`Found ${folders.length} folders to process\n`);

    let imported = 0;
    let skipped = 0;
    let errors = 0;

    for (const folder of folders) {
      try {
        const folderPath = path.join(LIBATION_PATH, folder.name);
        const files = await fs.readdir(folderPath);

        // Find metadata file
        const metadataFile = files.find((f) => f.endsWith('.metadata.json'));
        if (!metadataFile) {
          console.log(`⚠️  No metadata file in: ${folder.name}`);
          skipped++;
          continue;
        }

        // Read and parse metadata
        const metadataPath = path.join(folderPath, metadataFile);
        const metadataContent = await fs.readFile(metadataPath, 'utf-8');
        const metadata: LibationMetadata = JSON.parse(metadataContent);

        // Find audio and cover files (support both MP3 and M4B formats)
        const audioFile = files.find((f) => f.endsWith('.mp3') || f.endsWith('.m4b'));
        const coverFile = files.find((f) => f.endsWith('.jpg'));

        // Import to database
        await importBook(metadata, folderPath, audioFile, coverFile);

        console.log(`✅ Imported: ${metadata.title}`);
        imported++;
      } catch (error) {
        console.error(
          `❌ Error importing ${folder.name}:`,
          error instanceof Error ? error.message : error
        );
        errors++;
      }
    }

    console.log(`\n📊 Import Summary:`);
    console.log(`   ✅ Imported: ${imported}`);
    console.log(`   ⚠️  Skipped: ${skipped}`);
    console.log(`   ❌ Errors: ${errors}`);
  } catch (error) {
    console.error('❌ Fatal error:', error);
    throw error;
  }
}

export async function importBook(
  metadata: LibationMetadata,
  folderPath: string,
  audioFile?: string,
  coverFile?: string
) {
  // Check if book already exists
  const existingBook = await prisma.book.findUnique({
    where: { asin: metadata.asin },
  });

  if (existingBook) {
    console.log(`   ⏭️  Already exists, skipping: ${metadata.title}`);
    return;
  }

  // Process authors
  const authorIds: string[] = [];
  for (const authorData of metadata.authors || []) {
    // Try to find existing author by ASIN first, then by name
    let author = authorData.asin
      ? await prisma.author.findUnique({ where: { asin: authorData.asin } })
      : null;

    if (!author) {
      author = await prisma.author.findUnique({ where: { name: authorData.name } });
    }

    // If not found, create new author
    if (!author) {
      author = await prisma.author.create({
        data: {
          name: authorData.name,
          asin: authorData.asin,
        },
      });
    }

    authorIds.push(author.id);
  }

  // Process narrators
  const narratorIds: string[] = [];
  for (const narratorData of metadata.narrators || []) {
    // Try to find existing narrator by ASIN first, then by name
    let narrator = narratorData.asin
      ? await prisma.narrator.findUnique({ where: { asin: narratorData.asin } })
      : null;

    if (!narrator) {
      narrator = await prisma.narrator.findUnique({ where: { name: narratorData.name } });
    }

    // If not found, create new narrator
    if (!narrator) {
      narrator = await prisma.narrator.create({
        data: {
          name: narratorData.name,
          asin: narratorData.asin,
        },
      });
    }

    narratorIds.push(narrator.id);
  }

  // Process series
  const seriesData: Array<{ seriesId: string; sequence?: number }> = [];
  for (const seriesInfo of metadata.series || []) {
    const series = await prisma.series.upsert({
      where: { title: seriesInfo.title },
      update: {},
      create: {
        title: seriesInfo.title,
        asin: seriesInfo.asin,
      },
    });
    seriesData.push({
      seriesId: series.id,
      sequence: seriesInfo.sequence ? parseInt(seriesInfo.sequence, 10) : undefined,
    });
  }

  // Process categories
  const categoryIds: string[] = [];
  for (const categoryLadder of metadata.category_ladders || []) {
    let parentId: string | null = null;

    for (let i = 0; i < categoryLadder.ladder.length; i++) {
      const catData = categoryLadder.ladder[i];

      // Try to find existing category
      let category: { id: string; name: string; parentId: string | null; level: number } | null =
        await prisma.category.findFirst({
          where: {
            name: catData.name,
            parentId: parentId,
          },
        });

      // Create if not found
      if (!category) {
        category = await prisma.category.create({
          data: {
            name: catData.name,
            parentId: parentId,
            level: i,
          },
        });
      }

      // Only add the leaf category to the book
      if (i === categoryLadder.ladder.length - 1) {
        categoryIds.push(category.id);
      }

      parentId = category.id;
    }
  }

  // Deduplicate category IDs to avoid constraint violations
  const uniqueCategoryIds = [...new Set(categoryIds)];

  // Parse release date
  let releaseDate: Date | null = null;
  if (metadata.release_date) {
    try {
      releaseDate = new Date(metadata.release_date);
    } catch (e) {
      // Invalid date, skip
    }
  }

  // Store relative paths from media data directory
  const relativeFolderPath = path.relative(LIBATION_PATH, folderPath);

  // Extract chapters before creating book
  // Priority: M4B/ffprobe -> CUE file -> metadata.json
  let chapters: Array<{
    chapterNumber: number;
    title: string;
    startTime: number;
    endTime: number;
    duration: number;
  }> = [];

  if (audioFile) {
    const audioPath = path.join(folderPath, audioFile);

    // 1. Try ffprobe extraction from audio file (most accurate)
    try {
      const ffprobeChapters = await extractChapters(audioPath);
      if (ffprobeChapters.length > 0) {
        chapters = ffprobeChapters;
      }
    } catch {
      // ffprobe failed, continue to fallbacks
    }

    // 2. Try CUE file if no chapters yet
    if (chapters.length === 0) {
      try {
        const cuePath = await findCueFile(audioPath);
        if (cuePath) {
          let audioDuration: number | undefined;
          try {
            const audioMeta = await extractAudioMetadata(audioPath);
            audioDuration = audioMeta.duration;
          } catch {
            // Ignore duration errors
          }
          const cueChapters = await extractChaptersFromCueFile(cuePath, audioDuration);
          if (cueChapters && cueChapters.length > 0) {
            chapters = cueChapters;
          }
        }
      } catch {
        // CUE parsing failed, continue to fallback
      }
    }
  }

  // 3. Try metadata.json ChapterInfo if still no chapters
  if (chapters.length === 0) {
    try {
      const metadataJsonPath = path.join(folderPath, path.basename(folderPath) + '.metadata.json');
      const audibleChapters = await extractChaptersFromAudibleMetadata(metadataJsonPath);
      if (audibleChapters && audibleChapters.length > 0) {
        chapters = audibleChapters;
      }
    } catch {
      // No chapters available from any source
    }
  }

  // Create book with all relationships including chapters
  await prisma.book.create({
    data: {
      asin: metadata.asin,
      title: metadata.title,
      publisherSummary: metadata.publisher_summary,
      runtimeMinutes: metadata.runtime_length_min,
      releaseDate: releaseDate,
      publisher: metadata.publisher,
      coverUrl: coverFile ? path.join(relativeFolderPath, coverFile) : null,
      audioUrl: audioFile ? path.join(relativeFolderPath, audioFile) : null,
      metadata: metadata as any, // Store full metadata as JSON
      authors: {
        create: authorIds.map((authorId) => ({
          author: { connect: { id: authorId } },
        })),
      },
      narrators: {
        create: narratorIds.map((narratorId) => ({
          narrator: { connect: { id: narratorId } },
        })),
      },
      series: {
        create: seriesData.map(({ seriesId, sequence }) => ({
          series: { connect: { id: seriesId } },
          sequence: sequence,
        })),
      },
      categories: {
        create: uniqueCategoryIds.map((categoryId) => ({
          category: { connect: { id: categoryId } },
        })),
      },
      chapters: {
        create: chapters.map((ch) => ({
          chapterNumber: ch.chapterNumber,
          title: ch.title,
          startTime: ch.startTime,
          endTime: ch.endTime,
          duration: ch.duration,
        })),
      },
    },
  });
}

// Run the import only if this file is executed directly (not imported)
if (require.main === module) {
  (async () => {
    try {
      // First, seed the test user
      await seedTestUser();

      // Then import books
      await importBooks();

      console.log('\n✨ Import complete!');
    } catch (error) {
      console.error('\n💥 Import failed:', error);
      process.exit(1);
    } finally {
      await prisma.$disconnect();
    }
  })();
}

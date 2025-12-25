import { NextRequest, NextResponse } from 'next/server';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';

export async function GET(request: NextRequest) {
  try {
    // Authenticate user
    const user = await getAuthUserFromRequest(request);
    if (!user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      );
    }

    // Get download history with book details
    const downloads = await prisma.userDownload.findMany({
      where: { userId: user.id },
      include: {
        book: {
          select: {
            id: true,
            title: true,
          },
        },
      },
      orderBy: { downloadedAt: 'desc' },
      take: 50, // Limit to recent 50 downloads
    });

    // Count downloads in last 24 hours for daily limit info
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dailyCount = await prisma.userDownload.count({
      where: {
        userId: user.id,
        downloadedAt: {
          gte: twentyFourHoursAgo,
        },
      },
    });

    return NextResponse.json({
      downloads: downloads.map((d) => ({
        bookId: d.bookId,
        bookTitle: d.book.title,
        downloadedAt: d.downloadedAt.toISOString(),
        deviceId: d.deviceId,
      })),
      dailyCount,
    });
  } catch (error) {
    console.error('Download history fetch error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch download history' },
      { status: 500 }
    );
  }
}

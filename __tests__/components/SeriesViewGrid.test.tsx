import { render, screen } from '@testing-library/react';
import SeriesViewGrid, { SeriesViewItem } from '@/components/SeriesViewGrid';
import { Book } from '@/lib/types';

const mockBook: Book = {
  id: 'book-1',
  title: 'A Standalone Book',
  asin: 'BOOK1',
  archiveStatus: 'available' as const,
  authors: [{ id: 'author1', name: 'Author One', asin: 'AUTH1' }],
  narrators: [{ id: 'narrator1', name: 'Narrator One', asin: 'NARR1' }],
  series: [],
  categories: [],
  publisherSummary: 'Summary',
  runtimeMinutes: 120,
  coverUrl: '/book1.jpg',
  audioUrl: '/audio1.mp3',
  releaseDate: '2024-01-01',
};

describe('SeriesViewGrid', () => {
  const items: SeriesViewItem[] = [
    { series: { id: 'series-1', title: 'The Expanse', bookCount: 9, coverUrl: '/expanse.jpg' } },
    { book: mockBook },
  ];

  it('renders series tiles and book cards from the same feed', () => {
    render(<SeriesViewGrid items={items} />);
    expect(screen.getByText('The Expanse')).toBeInTheDocument();
    expect(screen.getByText('A Standalone Book')).toBeInTheDocument();
  });

  it('links series items to the series page and book items to the book page', () => {
    render(<SeriesViewGrid items={items} />);
    expect(screen.getByText('The Expanse').closest('a')).toHaveAttribute(
      'href',
      '/series/series-1'
    );
    expect(screen.getByText('A Standalone Book').closest('a')).toHaveAttribute(
      'href',
      '/books/book-1'
    );
  });

  it('prefers the series branch if an item somehow carries both', () => {
    render(
      <SeriesViewGrid
        items={[{ series: { id: 'series-2', title: 'Both Set', bookCount: 2 }, book: mockBook }]}
      />
    );
    expect(screen.getByText('Both Set')).toBeInTheDocument();
    expect(screen.queryByText('A Standalone Book')).not.toBeInTheDocument();
  });

  it('skips an item carrying neither series nor book', () => {
    render(<SeriesViewGrid items={[{}, ...items]} />);
    expect(screen.getByText('The Expanse')).toBeInTheDocument();
    expect(screen.getByText('A Standalone Book')).toBeInTheDocument();
  });

  it('shows skeleton placeholders while loading', () => {
    const { container } = render(<SeriesViewGrid items={[]} loading />);
    expect(container.querySelectorAll('.animate-pulse').length).toBeGreaterThan(0);
    expect(screen.queryByText('No series found')).not.toBeInTheDocument();
  });

  it('shows the empty state when there are no items', () => {
    render(<SeriesViewGrid items={[]} />);
    expect(screen.getByText('No series found')).toBeInTheDocument();
  });
});

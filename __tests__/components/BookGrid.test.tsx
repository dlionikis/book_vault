import { render, screen } from '@testing-library/react';
import BookGrid from '@/components/BookGrid';
import { Book } from '@/lib/types';

describe('BookGrid', () => {
  const mockBooks: Book[] = [
    {
      id: '1',
      title: 'Book One',
      asin: 'TEST1',
      authors: [{ id: 'author1', name: 'Author One', asin: 'AUTH1' }],
      narrators: [{ id: 'narrator1', name: 'Narrator One', asin: 'NARR1' }],
      series: [],
      categories: [],
      publisherSummary: 'Summary 1',
      runtimeMinutes: 120,
      coverUrl: '/book1.jpg',
      audioUrl: '/audio1.mp3',
      releaseDate: '2024-01-01',
    },
    {
      id: '2',
      title: 'Book Two',
      asin: 'TEST2',
      authors: [{ id: 'author2', name: 'Author Two', asin: 'AUTH2' }],
      narrators: [{ id: 'narrator2', name: 'Narrator Two', asin: 'NARR2' }],
      series: [],
      categories: [],
      publisherSummary: 'Summary 2',
      runtimeMinutes: 240,
      coverUrl: '/book2.jpg',
      audioUrl: '/audio2.mp3',
      releaseDate: '2024-01-02',
    },
  ];

  it('renders all books in a grid', () => {
    render(<BookGrid books={mockBooks} />);
    expect(screen.getByText('Book One')).toBeInTheDocument();
    expect(screen.getByText('Book Two')).toBeInTheDocument();
  });

  it('renders empty state when no books provided', () => {
    render(<BookGrid books={[]} />);
    expect(screen.queryByText('Book One')).not.toBeInTheDocument();
  });

  it('applies responsive grid classes', () => {
    const { container } = render(<BookGrid books={mockBooks} />);
    const grid = container.querySelector('.grid');
    expect(grid).toHaveClass('grid-cols-1');
    expect(grid).toHaveClass('sm:grid-cols-2');
    expect(grid).toHaveClass('lg:grid-cols-3');
    expect(grid).toHaveClass('xl:grid-cols-4');
  });

  it('renders correct number of book cards', () => {
    const { container } = render(<BookGrid books={mockBooks} />);
    const cards = container.querySelectorAll('a[href^="/books/"]');
    expect(cards).toHaveLength(2);
  });
});

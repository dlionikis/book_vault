import { render, screen } from '@testing-library/react';
import SeriesTile, { seriesCountLabel, SeriesTileSeries } from '@/components/SeriesTile';

describe('SeriesTile', () => {
  const baseSeries: SeriesTileSeries = {
    id: 'series-1',
    title: 'The Expanse',
    asin: 'SERIES1',
    bookCount: 9,
    coverUrl: '/covers/expanse.jpg',
  };

  it('renders the series title', () => {
    render(<SeriesTile series={baseSeries} />);
    expect(screen.getByText('The Expanse')).toBeInTheDocument();
  });

  it('links to the series detail page', () => {
    render(<SeriesTile series={baseSeries} />);
    const links = screen.getAllByRole('link');
    expect(links.length).toBeGreaterThan(0);
    links.forEach((link) => expect(link).toHaveAttribute('href', '/series/series-1'));
  });

  it('renders the cover image with an accessible alt text', () => {
    render(<SeriesTile series={baseSeries} />);
    expect(screen.getByAltText('Cover of The Expanse')).toBeInTheDocument();
  });

  it('renders a placeholder icon when the series has no derived cover', () => {
    const { container } = render(<SeriesTile series={{ ...baseSeries, coverUrl: null }} />);
    expect(screen.queryByAltText('Cover of The Expanse')).not.toBeInTheDocument();
    expect(container.querySelector('svg')).toBeInTheDocument();
  });

  it('marks the tile as a series so it is distinguishable from a book cover', () => {
    render(<SeriesTile series={baseSeries} />);
    expect(screen.getByText('Series')).toBeInTheDocument();
  });

  it('shows a plain book count in catalog scope (no ownedCount)', () => {
    render(<SeriesTile series={baseSeries} />);
    expect(screen.getByText('9 books')).toBeInTheDocument();
  });

  it('shows partial ownership in library scope', () => {
    render(<SeriesTile series={{ ...baseSeries, ownedCount: 3 }} />);
    expect(screen.getByText('3 of 9 in your library')).toBeInTheDocument();
  });

  it('shows a plain book count when the whole series is owned', () => {
    render(<SeriesTile series={{ ...baseSeries, ownedCount: 9 }} />);
    expect(screen.getByText('9 books')).toBeInTheDocument();
  });

  describe('seriesCountLabel', () => {
    it('singularizes a one-book series', () => {
      expect(seriesCountLabel({ ...baseSeries, bookCount: 1 })).toBe('1 book');
    });

    it('reports partial ownership when ownedCount is below bookCount', () => {
      expect(seriesCountLabel({ ...baseSeries, bookCount: 5, ownedCount: 2 })).toBe(
        '2 of 5 in your library'
      );
    });

    it('reports a plain count when ownedCount equals bookCount', () => {
      expect(seriesCountLabel({ ...baseSeries, bookCount: 5, ownedCount: 5 })).toBe('5 books');
    });

    it('treats an ownedCount of zero as partial ownership', () => {
      expect(seriesCountLabel({ ...baseSeries, bookCount: 5, ownedCount: 0 })).toBe(
        '0 of 5 in your library'
      );
    });
  });
});

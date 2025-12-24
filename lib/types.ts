// Base entity types (matching Prisma models but serializable for client components)

export interface Author {
  id: string;
  name: string;
  asin?: string | null;
  createdAt?: Date | string;
}

export interface Narrator {
  id: string;
  name: string;
  asin?: string | null;
  createdAt?: Date | string;
}

export interface Series {
  id: string;
  title: string;
  asin?: string | null;
  createdAt?: Date | string;
}

export interface Category {
  id: string;
  name: string;
  parentId?: string | null;
  level: number;
  createdAt?: Date | string;
}

// SeriesInfo (includes sequence from join table)
export interface SeriesInfo {
  id: string;
  title: string;
  asin?: string | null;
  sequence?: string | null;
}

// Transformed Book type (with URLs and flattened relationships)
export interface Book {
  id: string;
  asin: string;
  title: string;
  publisherSummary?: string | null;
  runtimeMinutes?: number | null;
  releaseDate?: Date | string | null;
  publisher?: string | null;
  coverUrl: string | null;
  audioUrl: string | null;
  authors: Author[];
  narrators: Narrator[];
  series: SeriesInfo[];
  categories?: Category[];
  metadata?: any; // JSON field from Prisma
  createdAt: Date | string;
}

// Pagination helper
export interface Pagination {
  page: number;
  limit: number;
  total: number;
  pages: number;
}

// Response types
export interface BooksResponse {
  books: Book[];
  pagination: Pagination;
}

export interface SearchResponse {
  query: string;
  books: Book[];
  pagination: Pagination;
}

// Entity-with-books types
export interface AuthorWithBooks extends Author {
  books: Book[];
  pagination: Pagination;
}

export interface NarratorWithBooks extends Narrator {
  books: Book[];
  pagination: Pagination;
}

export interface SeriesWithBooks extends Series {
  books: Book[];
  pagination: Pagination;
}

// Browse item types (with counts)
export interface AuthorBrowseItem extends Author {
  _count: { books: number };
}

export interface NarratorBrowseItem extends Narrator {
  _count: { books: number };
}

export interface SeriesBrowseItem extends Series {
  _count: { books: number };
}

export interface CategoryBrowseItem extends Category {
  _count: { books: number };
}

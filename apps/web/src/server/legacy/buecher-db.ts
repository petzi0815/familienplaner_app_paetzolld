// Portiert aus dem Original (`lib/books-db.ts`, E-Book-Downloader / Wunschliste). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN `db.close()` (Singleton darf nicht geschlossen werden).
//  - Kein `getBooksDb()`/CREATE TABLE mehr (Tabelle ist in der konsolidierten DB geseedet).
//  - Tabelle präfixiert: wishlist→ebook_wishlist.
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export interface Book {
  id: number;
  title: string;
  author?: string;
  publisher?: string;
  year?: string;
  category?: string;
  description?: string;
  cover_url?: string;
  isbn?: string;
  language?: string;
  status: 'gesucht' | 'heruntergeladen';
  source_id?: string;
  requested_by?: string;
  requested_at?: string;
  downloaded_at?: string;
  attempts: number;
  last_attempt?: string;
  notes?: string;
  reviews?: string;
  created_at: string;
  updated_at: string;
}

export function getAllBooks(filters?: {
  status?: string;
  year?: string;
  category?: string;
  q?: string;
}): Book[] {
  const db = getDb();
  let sql = 'SELECT * FROM ebook_wishlist WHERE 1=1';
  const params: unknown[] = [];

  if (filters?.status) {
    sql += ' AND status = ?';
    params.push(filters.status);
  }
  if (filters?.year) {
    sql += ' AND year = ?';
    params.push(filters.year);
  }
  if (filters?.category) {
    sql += ' AND category LIKE ?';
    params.push(`%${filters.category}%`);
  }
  if (filters?.q) {
    sql += ' AND (title LIKE ? OR author LIKE ?)';
    params.push(`%${filters.q}%`, `%${filters.q}%`);
  }

  sql += ' ORDER BY requested_at DESC, created_at DESC';

  const books = db.prepare(sql).all(...params) as Book[];
  return books;
}

export function getBook(id: number): Book | undefined {
  const db = getDb();
  const book = db.prepare('SELECT * FROM ebook_wishlist WHERE id = ?').get(id) as Book | undefined;
  return book;
}

export function addBook(data: Partial<Book>): number {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO ebook_wishlist (title, author, publisher, year, category, description, cover_url, isbn, language, status, source_id, requested_by, requested_at, downloaded_at, attempts, last_attempt, notes, reviews)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const result = stmt.run(
    data.title,
    data.author || null,
    data.publisher || null,
    data.year || null,
    data.category || null,
    data.description || null,
    data.cover_url || null,
    data.isbn || null,
    data.language || 'de',
    data.status || 'gesucht',
    data.source_id || null,
    data.requested_by || 'Elita',
    data.requested_at || null,
    data.downloaded_at || null,
    data.attempts || 0,
    data.last_attempt || null,
    data.notes || null,
    data.reviews || null,
  );
  return result.lastInsertRowid as number;
}

export function updateBook(id: number, data: Partial<Book>): boolean {
  const db = getDb();
  const fields: string[] = [];
  const params: unknown[] = [];

  const allowedFields = ['title', 'author', 'publisher', 'year', 'category', 'description', 'cover_url', 'isbn', 'language', 'status', 'source_id', 'requested_by', 'requested_at', 'downloaded_at', 'attempts', 'last_attempt', 'notes', 'reviews'];

  for (const key of allowedFields) {
    if (key in data) {
      fields.push(`${key} = ?`);
      params.push((data as Record<string, unknown>)[key]);
    }
  }

  if (fields.length === 0) {
    return false;
  }

  fields.push("updated_at = datetime('now')");
  params.push(id);

  const result = db.prepare(`UPDATE ebook_wishlist SET ${fields.join(', ')} WHERE id = ?`).run(...params);
  return result.changes > 0;
}

export function deleteBook(id: number): boolean {
  const db = getDb();
  const result = db.prepare('DELETE FROM ebook_wishlist WHERE id = ?').run(id);
  return result.changes > 0;
}

export function getCategories(): string[] {
  const db = getDb();
  const rows = db.prepare("SELECT DISTINCT category FROM ebook_wishlist WHERE category IS NOT NULL AND category != '' ORDER BY category").all() as { category: string }[];
  return rows.map(r => r.category);
}

export function getYears(): string[] {
  const db = getDb();
  const rows = db.prepare("SELECT DISTINCT year FROM ebook_wishlist WHERE year IS NOT NULL AND year != '' ORDER BY year DESC").all() as { year: string }[];
  return rows.map(r => r.year);
}

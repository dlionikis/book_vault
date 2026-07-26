import { readFileSync } from 'fs';
import { join } from 'path';

/**
 * Regression guard for the server/client boundary.
 *
 * `SeriesModeSection` is a Client Component rendered by two Server Components.
 * Passing it a render prop (any function) throws "Functions cannot be passed
 * directly to Client Components" at request time and takes the whole page down.
 *
 * Component unit tests can't catch this — they render entirely on the client,
 * where function props work fine. Only a real request (E2E) or this source-level
 * check will. See docs/plans/series-view-toggle-implementation.md, Phase 5.
 */
describe('SeriesModeSection server/client boundary', () => {
  const PAGES = [
    { name: 'app/page.tsx', path: join(process.cwd(), 'app/page.tsx') },
    { name: 'app/library/page.tsx', path: join(process.cwd(), 'app/library/page.tsx') },
  ];

  it.each(PAGES)('$name renders SeriesModeSection', ({ path }) => {
    expect(readFileSync(path, 'utf8')).toContain('<SeriesModeSection');
  });

  it.each(PAGES)('$name is a Server Component (no "use client")', ({ path }) => {
    const source = readFileSync(path, 'utf8');
    expect(source).not.toMatch(/^\s*['"]use client['"]/m);
  });

  /**
   * Slices out a JSX element's attribute list.
   *
   * Can't just scan to the first `>` — a nested element in a prop
   * (`booksModeControls={<SortDropdown />}`) contains one. Track brace depth
   * and stop at the first `>` sitting at depth zero.
   */
  function attributeList(source: string, tag: string): string {
    const start = source.indexOf(`<${tag}`);
    if (start === -1) throw new Error(`<${tag} not found`);

    let depth = 0;
    for (let i = start + tag.length + 1; i < source.length; i++) {
      const char = source[i];
      if (char === '{') depth++;
      else if (char === '}') depth--;
      else if (char === '>' && depth === 0) return source.slice(start, i);
    }
    throw new Error(`unterminated <${tag} tag`);
  }

  it.each(PAGES)('$name passes no function props to SeriesModeSection', ({ path }) => {
    const props = attributeList(readFileSync(path, 'utf8'), 'SeriesModeSection');

    // e.g. `renderHeading={({ mode }) => ...}` or `onFoo={function () {}}`
    expect(props).not.toMatch(/\w+=\{\s*(\([^)]*\)|\w+)\s*=>/);
    expect(props).not.toMatch(/\w+=\{\s*(async\s+)?function\b/);
  });

  it('attributeList spans the whole prop list, past nested JSX props', () => {
    // Guards the guard: a naive indexOf('>') stops inside `{<SortDropdown />}`
    // and would silently skip every prop after it.
    const props = attributeList(readFileSync(PAGES[0].path, 'utf8'), 'SeriesModeSection');
    expect(props).toContain('booksModeControls={<SortDropdown />}');
    expect(props).toContain('seriesHeadingTitle');
  });
});

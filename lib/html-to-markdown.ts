import TurndownService from 'turndown';

// Create a reusable turndown instance with custom rules
const turndownService = new TurndownService({
  headingStyle: 'atx',
  codeBlockStyle: 'fenced',
  emDelimiter: '*',
  strongDelimiter: '**',
  bulletListMarker: '-',
});

/**
 * Convert HTML to Markdown
 * Used to convert book descriptions from Libation HTML format to Markdown
 * for consistent rendering across web and mobile clients
 */
export function htmlToMarkdown(html: string | null | undefined): string | null {
  if (!html) return null;

  try {
    // Convert HTML to Markdown
    const markdown = turndownService.turndown(html);

    // Clean up excessive newlines
    return markdown.replace(/\n{3,}/g, '\n\n').trim();
  } catch (error) {
    console.error('Error converting HTML to Markdown:', error);
    // Return original HTML as fallback
    return html;
  }
}

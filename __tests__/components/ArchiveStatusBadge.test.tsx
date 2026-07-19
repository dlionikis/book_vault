import { render, screen } from '@testing-library/react';
import ArchiveStatusBadge from '@/components/ArchiveStatusBadge';

describe('ArchiveStatusBadge', () => {
  it('renders nothing when available', () => {
    const { container } = render(<ArchiveStatusBadge status="available" />);
    expect(container).toBeEmptyDOMElement();
  });

  it('shows an Archived label (full form)', () => {
    render(<ArchiveStatusBadge status="archived" />);
    expect(screen.getByText('Archived')).toBeInTheDocument();
  });

  it('shows a Restoring label (full form)', () => {
    render(<ArchiveStatusBadge status="restoring" />);
    expect(screen.getByText('Restoring')).toBeInTheDocument();
  });

  it('compact form exposes an accessible label without visible text', () => {
    render(<ArchiveStatusBadge status="archived" compact />);
    // aria-label present; the word isn't rendered as visible text in compact mode
    expect(screen.getByLabelText('Archived')).toBeInTheDocument();
    expect(screen.queryByText('Archived')).not.toBeInTheDocument();
  });
});

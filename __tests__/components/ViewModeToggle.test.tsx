import { render, screen, fireEvent, act } from '@testing-library/react';
import ViewModeToggle, {
  useViewMode,
  CATALOG_VIEW_MODE_KEY,
  LIBRARY_VIEW_MODE_KEY,
} from '@/components/ViewModeToggle';

describe('ViewModeToggle', () => {
  it('renders both modes', () => {
    render(<ViewModeToggle mode="books" onChange={jest.fn()} />);
    expect(screen.getByRole('button', { name: 'Books' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Series' })).toBeInTheDocument();
  });

  it('marks the active mode with aria-pressed', () => {
    render(<ViewModeToggle mode="series" onChange={jest.fn()} />);
    expect(screen.getByRole('button', { name: 'Series' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: 'Books' })).toHaveAttribute('aria-pressed', 'false');
  });

  it('calls onChange with the selected mode', () => {
    const onChange = jest.fn();
    render(<ViewModeToggle mode="books" onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: 'Series' }));
    expect(onChange).toHaveBeenCalledWith('series');
  });
});

describe('useViewMode', () => {
  // Exercises the hook through a tiny host component rather than renderHook,
  // matching how the real pages consume it.
  function Harness({ storageKey }: { storageKey: string }) {
    const { mode, setMode, hydrated } = useViewMode(storageKey);
    return (
      <div>
        <span data-testid="mode">{mode}</span>
        <span data-testid="hydrated">{String(hydrated)}</span>
        <ViewModeToggle mode={mode} onChange={setMode} />
      </div>
    );
  }

  beforeEach(() => {
    window.localStorage.clear();
  });

  it('defaults to books mode with nothing stored', () => {
    render(<Harness storageKey={CATALOG_VIEW_MODE_KEY} />);
    expect(screen.getByTestId('mode')).toHaveTextContent('books');
  });

  it('restores a persisted series mode after mount', () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    render(<Harness storageKey={CATALOG_VIEW_MODE_KEY} />);
    expect(screen.getByTestId('mode')).toHaveTextContent('series');
    expect(screen.getByTestId('hydrated')).toHaveTextContent('true');
  });

  it('persists a mode change to localStorage', () => {
    render(<Harness storageKey={CATALOG_VIEW_MODE_KEY} />);
    fireEvent.click(screen.getByRole('button', { name: 'Series' }));
    expect(window.localStorage.getItem(CATALOG_VIEW_MODE_KEY)).toBe('series');
    expect(screen.getByTestId('mode')).toHaveTextContent('series');
  });

  it('keeps Catalog and Library modes independent', () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'series');
    render(<Harness storageKey={LIBRARY_VIEW_MODE_KEY} />);
    // Library has no stored preference of its own, so it stays on books.
    expect(screen.getByTestId('mode')).toHaveTextContent('books');
  });

  it('ignores an unrecognized stored value', () => {
    window.localStorage.setItem(CATALOG_VIEW_MODE_KEY, 'nonsense');
    render(<Harness storageKey={CATALOG_VIEW_MODE_KEY} />);
    expect(screen.getByTestId('mode')).toHaveTextContent('books');
  });

  it('falls back to books mode when localStorage reads throw', () => {
    const getItem = jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('storage disabled');
    });

    render(<Harness storageKey={CATALOG_VIEW_MODE_KEY} />);
    expect(screen.getByTestId('mode')).toHaveTextContent('books');

    getItem.mockRestore();
  });

  it('does not crash when localStorage writes throw', () => {
    const setItem = jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('storage full');
    });

    render(<Harness storageKey={CATALOG_VIEW_MODE_KEY} />);
    act(() => {
      fireEvent.click(screen.getByRole('button', { name: 'Series' }));
    });

    // localStorage is the single source of truth, so an unwritable store means
    // the mode honestly stays put rather than showing a preference that would
    // silently vanish on the next page load.
    expect(screen.getByTestId('mode')).toHaveTextContent('books');

    setItem.mockRestore();
  });
});

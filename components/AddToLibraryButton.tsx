'use client';

import { useState, useEffect } from 'react';
import { useSession } from 'next-auth/react';

interface AddToLibraryButtonProps {
  bookId: string;
  seriesId?: string;
  size?: 'small' | 'medium' | 'large';
  showSeriesOption?: boolean;
  onSuccess?: () => void;
}

export default function AddToLibraryButton({
  bookId,
  seriesId,
  size = 'medium',
  showSeriesOption = false,
  onSuccess,
}: AddToLibraryButtonProps) {
  const { data: session } = useSession();
  const [inLibrary, setInLibrary] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showDialog, setShowDialog] = useState(false);

  // Check if book is in library
  useEffect(() => {
    if (!session?.user) return;

    async function checkLibrary() {
      try {
        const res = await fetch(`/api/library/check?bookId=${bookId}`);
        const data = await res.json();
        setInLibrary(data.inLibrary);
      } catch (error) {
        console.error('Error checking library:', error);
      }
    }

    checkLibrary();
  }, [bookId, session]);

  const handleAddBook = async () => {
    if (!session?.user) {
      window.location.href = '/auth/login';
      return;
    }

    setLoading(true);
    try {
      const res = await fetch('/api/library', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bookId }),
      });

      if (res.ok) {
        setInLibrary(true);
        onSuccess?.();
      }
    } catch (error) {
      console.error('Error adding to library:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRemoveBook = async () => {
    setLoading(true);
    try {
      const res = await fetch(`/api/library/${bookId}`, {
        method: 'DELETE',
      });

      if (res.ok) {
        setInLibrary(false);
        onSuccess?.();
      }
    } catch (error) {
      console.error('Error removing from library:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleAddSeries = async () => {
    if (!seriesId) return;

    setLoading(true);
    try {
      const res = await fetch(`/api/library/series/${seriesId}`, {
        method: 'POST',
      });

      if (res.ok) {
        setInLibrary(true);
        setShowDialog(false);
        onSuccess?.();
      }
    } catch (error) {
      console.error('Error adding series to library:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRemoveSeries = async () => {
    if (!seriesId) return;

    setLoading(true);
    try {
      const res = await fetch(`/api/library/series/${seriesId}`, {
        method: 'DELETE',
      });

      if (res.ok) {
        setInLibrary(false);
        setShowDialog(false);
        onSuccess?.();
      }
    } catch (error) {
      console.error('Error removing series from library:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleClick = () => {
    if (showSeriesOption && seriesId) {
      setShowDialog(true);
    } else if (inLibrary) {
      handleRemoveBook();
    } else {
      handleAddBook();
    }
  };

  const sizeClasses = {
    small: 'px-3 py-1.5 text-sm',
    medium: 'px-4 py-2 text-base',
    large: 'px-6 py-3 text-lg',
  };

  return (
    <>
      <button
        onClick={handleClick}
        disabled={loading}
        className={`${sizeClasses[size]} ${
          inLibrary
            ? 'bg-green-600 hover:bg-green-700 dark:bg-green-700 dark:hover:bg-green-800'
            : 'bg-blue-600 hover:bg-blue-700 dark:bg-blue-700 dark:hover:bg-blue-800'
        } text-white rounded-md font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2`}
      >
        {loading ? (
          <>
            <svg
              className="animate-spin h-4 w-4"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              ></circle>
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              ></path>
            </svg>
            <span>Loading...</span>
          </>
        ) : (
          <>
            {inLibrary ? (
              <>
                <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span>In Library</span>
              </>
            ) : (
              <>
                <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M12 4v16m8-8H4"
                  />
                </svg>
                <span>Add to Library</span>
              </>
            )}
          </>
        )}
      </button>

      {/* Series Dialog */}
      {showDialog && (
        <div
          className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
          onClick={() => setShowDialog(false)}
        >
          <div
            className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
              {inLibrary ? 'Remove from Library' : 'Add to Library'}
            </h3>
            <p className="text-gray-600 dark:text-gray-400 mb-6">
              This book is part of a series. Would you like to {inLibrary ? 'remove' : 'add'} the
              entire series or just this book?
            </p>
            <div className="flex flex-col gap-3">
              <button
                onClick={inLibrary ? handleRemoveSeries : handleAddSeries}
                disabled={loading}
                className="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 dark:bg-blue-700 dark:hover:bg-blue-800 text-white rounded-md font-medium transition-colors disabled:opacity-50"
              >
                {inLibrary ? 'Remove' : 'Add'} Entire Series
              </button>
              <button
                onClick={inLibrary ? handleRemoveBook : handleAddBook}
                disabled={loading}
                className="w-full px-4 py-2 bg-gray-600 hover:bg-gray-700 dark:bg-gray-700 dark:hover:bg-gray-800 text-white rounded-md font-medium transition-colors disabled:opacity-50"
              >
                {inLibrary ? 'Remove' : 'Add'} Just This Book
              </button>
              <button
                onClick={() => setShowDialog(false)}
                className="w-full px-4 py-2 bg-gray-200 hover:bg-gray-300 dark:bg-gray-600 dark:hover:bg-gray-500 text-gray-900 dark:text-white rounded-md font-medium transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

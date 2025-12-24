/**
 * Calculate average rating from an array of reviews
 * @param reviews - Array of review objects with rating property
 * @returns Average rating rounded to one decimal place, or 0 if no reviews
 */
export function calculateRating(reviews: { rating: number }[]): number {
  if (!reviews || reviews.length === 0) {
    return 0;
  }

  const sum = reviews.reduce((acc, review) => acc + review.rating, 0);
  const average = sum / reviews.length;

  return Math.round(average * 10) / 10;
}

export type FestivalLanguage = 'en' | 'es';

type TranslationKey = keyof typeof messages.en;

const messages = {
  en: {
    map: 'Map', rankings: 'Rankings', tapas: 'Tapas', language: 'Language', star: 'star', stars: 'stars', signIn: 'Sign in', signedIn: 'Signed in', logOut: 'Log out', writeReview: 'Write a review', saveReview: 'Save review', editReview: 'Edit review', yourReview: 'Your review', noReviewsYet: 'No reviews yet', reviewSaved: 'Review saved.', festivalVisitor: 'Festival visitor', showReviews: 'Show reviews', hideReviews: 'Hide reviews', chooseRatingFirst: 'Choose a star rating before saving a review.', festivalMap: 'Festival map', mapped: 'mapped', selectMarker: 'Select a marker to see the establishment, its tapas and current ratings.', participating: 'Participating', closedOrWithdrawn: 'Closed or withdrawn', noCoordinates: 'No establishment coordinates are available yet. All establishments remain in the list below.', locationUnavailable: 'Location unavailable',
    loading: 'Loading festival…', unableToLoad: 'Unable to load festival data:', noFestival: 'No published festival is available yet.', standardTapaPrice: 'Standard tapa price:', liveRankings: 'Live tapa rankings', rankingDescription: 'Ranking blends each average with the festival-wide average using a five-rating baseline, so one vote does not dominate.', ratings: 'ratings', goodExcellent: '4–5★',
    withdrawn: 'Withdrawn', closed: 'Closed', openingHours: 'Opening hours:', phone: 'Phone:', whatsapp: 'WhatsApp:', website: 'Website', facebook: 'Facebook', publicRating: 'Public rating:', unrated: 'Unrated', rateThisTapa: 'Rate this tapa', chooseStars: 'Choose 1–5 stars, then', signInToRate: 'sign in to submit your rating', yourRating: 'Your rating:', notRatedYet: 'Not rated yet', outOfFive: 'out of 5 stars', removeRating: 'Remove my rating', signInAtAdmin: 'Sign in at /admin to rate this tapa.', noPublishedTapas: 'No published tapas.',
  },
  es: {
    map: 'Mapa', rankings: 'Clasificación', tapas: 'Tapas', language: 'Idioma', star: 'estrella', stars: 'estrellas', signIn: 'Iniciar sesión', signedIn: 'Sesión iniciada', logOut: 'Cerrar sesión', writeReview: 'Escribe una reseña', saveReview: 'Guardar reseña', editReview: 'Editar reseña', yourReview: 'Tu reseña', noReviewsYet: 'Aún no hay reseñas', reviewSaved: 'Reseña guardada.', festivalVisitor: 'Visitante', showReviews: 'Mostrar reseñas', hideReviews: 'Ocultar reseñas', chooseRatingFirst: 'Elige una valoración antes de guardar una reseña.', festivalMap: 'Mapa del festival', mapped: 'en el mapa', selectMarker: 'Selecciona un marcador para ver el establecimiento, sus tapas y sus valoraciones actuales.', participating: 'Participante', closedOrWithdrawn: 'Cerrado o retirado', noCoordinates: 'Todavía no hay coordenadas disponibles. Todos los establecimientos siguen apareciendo en la lista.', locationUnavailable: 'Ubicación no disponible',
    loading: 'Cargando festival…', unableToLoad: 'No se han podido cargar los datos del festival:', noFestival: 'Todavía no hay ningún festival publicado.', standardTapaPrice: 'Precio estándar de la tapa:', liveRankings: 'Clasificación de tapas en directo', rankingDescription: 'La clasificación combina cada media con la media del festival usando una base de cinco valoraciones, para que un solo voto no domine.', ratings: 'valoraciones', goodExcellent: '4–5★',
    withdrawn: 'Retirada', closed: 'Cerrado', openingHours: 'Horario:', phone: 'Teléfono:', whatsapp: 'WhatsApp:', website: 'Web', facebook: 'Facebook', publicRating: 'Valoración pública:', unrated: 'Sin valorar', rateThisTapa: 'Valora esta tapa', chooseStars: 'Elige de 1 a 5 estrellas y después', signInToRate: 'inicia sesión para enviar tu valoración', yourRating: 'Tu valoración:', notRatedYet: 'Aún sin valorar', outOfFive: 'de 5 estrellas', removeRating: 'Eliminar mi valoración', signInAtAdmin: 'Inicia sesión en /admin para valorar esta tapa.', noPublishedTapas: 'No hay tapas publicadas.',
  },
} as const;

export function useFestivalLanguage() {
  const language = useState<FestivalLanguage>('festival-language', () => 'en');
  const t = (key: TranslationKey) => messages[language.value][key];
  const localized = (english?: string | null, spanish?: string | null) => language.value === 'es' ? spanish || english || '' : english || spanish || '';
  const setLanguage = (value: FestivalLanguage) => {
    language.value = value;
    if (import.meta.client) localStorage.setItem('festival-language', value);
  };

  onMounted(() => {
    const saved = localStorage.getItem('festival-language');
    if (saved === 'en' || saved === 'es') language.value = saved;
  });

  return { language, setLanguage, t, localized };
}

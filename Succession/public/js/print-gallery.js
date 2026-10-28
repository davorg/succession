(() => {
  'use strict';

  const modal = document.getElementById('printGalleryModal');
  const carouselElement = document.getElementById('printGalleryCarousel');
  const position = document.getElementById('printGalleryPosition');
  if (!modal || !carouselElement || !position || !window.bootstrap?.Carousel) return;

  const slides = carouselElement.querySelectorAll('.carousel-item');
  const carousel = window.bootstrap.Carousel.getOrCreateInstance(carouselElement, {
    interval: false,
    keyboard: false,
    touch: true,
  });
  const updatePosition = index => {
    const text = `${index + 1} of ${slides.length}`;
    if (position.textContent !== text) position.textContent = text;
  };

  modal.addEventListener('show.bs.modal', event => {
    const index = Number(event.relatedTarget?.dataset.printSlide ?? 0);
    if (!Number.isInteger(index) || index < 0 || index >= slides.length) return;
    carousel.to(index);
    updatePosition(index);
  });
  carouselElement.addEventListener('slid.bs.carousel', event => updatePosition(event.to));
  modal.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault();
      if (event.key === 'ArrowLeft') carousel.prev();
      else carousel.next();
    }
  });
})();

(() => {
  'use strict';
  const form = document.getElementById('print-form');
  if (!form) return;
  const date = document.getElementById('print-date');
  const order = document.getElementById('print-order');
  const submit = document.getElementById('print-submit');
  const preview = document.getElementById('print-preview');
  const image = document.getElementById('print-image');
  const placeholder = document.getElementById('print-placeholder');
  const status = document.getElementById('print-status');
  const error = document.getElementById('print-error');
  let activeURL;

  document.querySelectorAll('.print-example').forEach(button => {
    button.addEventListener('click', () => {
      if (submit.disabled) return;
      date.value = button.dataset.date;
      form.requestSubmit();
    });
  });

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (submit.disabled || !form.reportValidity()) return;
    const selectedDate = date.value;
    const selectedOrder = order.value;
    submit.disabled = true;
    error.hidden = true;
    image.hidden = true;
    placeholder.hidden = true;
    preview.setAttribute('aria-busy', 'true');
    status.textContent = 'Working… Generating your print preview.';
    let nextURL;
    try {
      const params = new URLSearchParams({date: selectedDate, order: selectedOrder});
      const response = await fetch(`/print.png?${params}`);
      if (!response.ok) {
        const message = response.status === 400 || response.status === 422
          ? await response.text() : 'We couldn’t generate this preview. Please try again later.';
        throw new Error(message);
      }
      if (!(response.headers.get('Content-Type') || '').startsWith('image/png')) {
        throw new Error('The preview could not be loaded. Please try again.');
      }
      nextURL = URL.createObjectURL(await response.blob());
      image.src = nextURL;
      await image.decode();
      if (activeURL) URL.revokeObjectURL(activeURL);
      activeURL = nextURL;
      nextURL = undefined;
      image.alt = `British line of succession on ${selectedDate}, in ${selectedOrder} order. Specimen preview.`;
      image.hidden = false;
      status.textContent = 'Your preview is ready.';
    } catch (failure) {
      if (nextURL) URL.revokeObjectURL(nextURL);
      error.textContent = failure instanceof TypeError
        ? 'Unable to load the preview. Check your connection and try again.' : failure.message;
      error.hidden = false;
      placeholder.hidden = false;
      status.textContent = '';
    } finally {
      submit.disabled = false;
      preview.setAttribute('aria-busy', 'false');
    }
  });
})();

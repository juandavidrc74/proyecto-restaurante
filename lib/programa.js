async function actualizarAvisos() {
    const avisos = document.querySelector("#AVISOS[data-opcion]");
    if (!avisos) return;

    try {
        const opcion = encodeURIComponent(avisos.dataset.opcion);
        const respuesta = await fetch(`?opcion=${opcion}`, { credentials: "same-origin" });
        if (!respuesta.ok) return;
        const html = await respuesta.text();
        const documento = new DOMParser().parseFromString(html, "text/html");
        const nuevosAvisos = documento.querySelector("#AVISOS");
        if (nuevosAvisos) avisos.innerHTML = nuevosAvisos.innerHTML;
    } catch (error) {
        // La página mantiene los avisos visibles si falla temporalmente la conexión.
    }
}

window.setInterval(actualizarAvisos, 30000);

document.addEventListener("DOMContentLoaded", function () {
  const elements = {
    imageInput: document.getElementById("svgImageInput"),
    uploadArea: document.getElementById("svgUploadArea"),
    fileStatus: document.getElementById("svgFileStatus"),
    fileName: document.getElementById("svgFileName"),
    fileSize: document.getElementById("svgFileSize"),
    preview: document.getElementById("svgPreview"),
    removePreview: document.getElementById("svgRemovePreview"),
    preset: document.getElementById("svgPreset"),
    hierarchical: document.getElementById("svgHierarchical"),
    mode: document.getElementById("svgMode"),
    filterSpeckle: document.getElementById("svgFilterSpeckle"),
    colorPrecision: document.getElementById("svgColorPrecision"),
    gradientStep: document.getElementById("svgGradientStep"),
    simplify: document.getElementById("svgSimplify"),
    maxColors: document.getElementById("svgMaxColors"),
    optimize: document.getElementById("svgOptimize"),
    pathPrecision: document.getElementById("svgPathPrecision"),
    threshold: document.getElementById("svgThreshold"),
    adaptive: document.getElementById("svgAdaptive"),
    convertBtn: document.getElementById("svgConvertBtn"),
    progress: document.getElementById("svgProgress"),
    result: document.getElementById("svgResult"),
    resultPreview: document.getElementById("svgResultPreview"),
    originalSize: document.querySelector(".svg-original-size"),
    vectorSize: document.querySelector(".svg-vector-size"),
    download: document.getElementById("svgDownload")
  };

  if (!elements.imageInput || !elements.uploadArea || !elements.convertBtn) {
    console.error("Required SVG converter elements not found");
    return;
  }

  const MAX_FILE_SIZE = 32 * 1024 * 1024; // 32MB
  let currentFile = null;
  let resultUrl = null;

  setupEventListeners();

  function setupEventListeners() {
    elements.imageInput.addEventListener("change", (e) => {
      const file = e.target.files[0];
      if (file) handleFileSelect(file);
    });

    if (elements.removePreview) {
      elements.removePreview.addEventListener("click", (e) => {
        e.preventDefault();
        resetSelection();
      });
    }

    elements.convertBtn.addEventListener("click", handleConvert);

    setupDragAndDrop();
  }

  function setupDragAndDrop() {
    elements.uploadArea.addEventListener("dragover", (e) => {
      e.preventDefault();
      elements.uploadArea.classList.add("border-green-500");
    });

    elements.uploadArea.addEventListener("dragleave", (e) => {
      e.preventDefault();
      elements.uploadArea.classList.remove("border-green-500");
    });

    elements.uploadArea.addEventListener("drop", (e) => {
      e.preventDefault();
      elements.uploadArea.classList.remove("border-green-500");
      if (e.dataTransfer.files.length) {
        elements.imageInput.files = e.dataTransfer.files;
        handleFileSelect(e.dataTransfer.files[0]);
      }
    });
  }

  function handleFileSelect(file) {
    if (!file.type.startsWith("image/")) {
      showError(I18n.t("err.invalidImage"));
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      showError(I18n.t("err.fileTooLarge"));
      return;
    }

    currentFile = file;
    elements.fileName.textContent = file.name;
    elements.fileSize.textContent = " (" + (file.size / (1024 * 1024)).toFixed(2) + " MB)";
    elements.fileStatus.classList.remove("hidden");
    elements.convertBtn.disabled = false;

    const reader = new FileReader();
    reader.onload = (e) => {
      const img = elements.preview.querySelector("img") || document.createElement("img");
      img.src = e.target.result;
      img.alt = I18n.t("svg.previewAlt");
      if (!elements.preview.contains(img)) {
        elements.preview.appendChild(img);
      }
      elements.preview.classList.remove("hidden");
      elements.originalSize.textContent = (file.size / 1024).toFixed(2) + " KB";
    };
    reader.readAsDataURL(file);
  }

  function buildFormData() {
    const formData = new FormData();
    formData.append("image", currentFile);

    if (elements.preset.value) formData.append("preset", elements.preset.value);
    if (elements.hierarchical.value) formData.append("hierarchical", elements.hierarchical.value);
    if (elements.mode.value) formData.append("mode", elements.mode.value);
    if (elements.filterSpeckle.value) formData.append("filterSpeckle", elements.filterSpeckle.value);
    if (elements.colorPrecision.value) formData.append("colorPrecision", elements.colorPrecision.value);
    if (elements.gradientStep.value) formData.append("gradientStep", elements.gradientStep.value);
    if (elements.simplify.value) formData.append("simplify", elements.simplify.value);
    if (elements.maxColors.value) formData.append("maxColors", elements.maxColors.value);
    if (elements.optimize.value) formData.append("optimize", elements.optimize.value);
    if (elements.pathPrecision.value) formData.append("pathPrecision", elements.pathPrecision.value);

    if (elements.preset.value === "bw" && !elements.adaptive.checked) {
      const threshold = parseInt(elements.threshold.value || "128", 10);
      if (isNaN(threshold) || threshold < 0 || threshold > 255) {
        showError(I18n.t("svg.err.thresholdRange"));
        return null;
      }
      formData.append("threshold", String(threshold));
    }
    if (elements.preset.value === "bw" && elements.adaptive.checked) {
      formData.append("adaptive", "true");
    }

    return formData;
  }

  async function handleConvert() {
    if (!currentFile) {
      showError(I18n.t("svg.err.noFile"));
      return;
    }

    const formData = buildFormData();
    if (!formData) return;

    showProgress();
    elements.convertBtn.disabled = true;

    try {
      const response = await fetch("/process/svg", {
        method: "POST",
        body: formData
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        console.error("Server response:", errorData);
        throw new Error(I18n.serverError(errorData.error));
      }

      const blob = await response.blob();
      if (resultUrl) URL.revokeObjectURL(resultUrl);
      resultUrl = URL.createObjectURL(blob);

      elements.resultPreview.src = resultUrl;
      elements.vectorSize.textContent = (blob.size / 1024).toFixed(2) + " KB";
      elements.download.href = resultUrl;
      elements.result.classList.remove("hidden");
    } catch (error) {
      console.error("SVG conversion error:", error);
      showError(error.message || I18n.t("svg.err.failed"));
    } finally {
      hideProgress();
      elements.convertBtn.disabled = false;
    }
  }

  function showProgress() {
    elements.progress.classList.remove("hidden");
    elements.result.classList.add("hidden");
  }

  function hideProgress() {
    elements.progress.classList.add("hidden");
  }

  function showError(message) {
    const errorDiv = document.createElement("div");
    errorDiv.className = "bg-red-50 border-l-4 border-red-400 p-4";
    errorDiv.innerHTML =
      '<div class="flex">' +
      '<div class="flex-shrink-0">' +
      '<svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">' +
      '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>' +
      "</svg>" +
      "</div>" +
      '<div class="ml-3"><p class="text-sm text-red-700">' + message + "</p></div>" +
      "</div>";
    elements.uploadArea.insertAdjacentElement("beforebegin", errorDiv);
    setTimeout(() => errorDiv.remove(), 5000);
  }

  function resetSelection() {
    currentFile = null;
    elements.imageInput.value = "";
    elements.preview.classList.add("hidden");
    elements.fileStatus.classList.add("hidden");
    elements.convertBtn.disabled = true;
    elements.result.classList.add("hidden");
    if (resultUrl) {
      URL.revokeObjectURL(resultUrl);
      resultUrl = null;
    }
  }
});
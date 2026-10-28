// On-device transcription for the field app. Whisper runs in the browser
// (Apache-2.0, no API key). Language "arabic" keeps Egyptian colloquial in
// Arabic script instead of translating it.

const MODEL = 'Xenova/whisper-base';

let pipelinePromise;
let progressHandler;

function report(message) {
    if (progressHandler) progressHandler(message);
}

export function onTranscribeProgress(handler) {
    progressHandler = handler;
}

async function loadPipeline() {
    if (!pipelinePromise) {
        pipelinePromise = (async () => {
            const { pipeline, env } = await import('@huggingface/transformers');
            env.allowLocalModels = false;
            env.useBrowserCache = true;
            report('Downloading Whisper for Arabic…');
            return pipeline('automatic-speech-recognition', MODEL, {
                dtype: 'q8',
                device: 'wasm',
                progress_callback(data) {
                    if (data.status === 'progress' && data.total) {
                        report(`Downloading Whisper… ${Math.round((100 * data.loaded) / data.total)}%`);
                    } else if (data.status === 'ready') {
                        report('Whisper is ready on this tablet.');
                    }
                }
            });
        })().catch((error) => {
            pipelinePromise = undefined;
            throw error;
        });
    }
    return pipelinePromise;
}

export function prepareTranscriber() {
    return loadPipeline().then(() => {
        report('Whisper is ready on this tablet.');
        return 'ready';
    });
}

async function decodeTo16k(blob) {
    const ctx = new AudioContext();
    try {
        const decoded = await ctx.decodeAudioData(await blob.arrayBuffer());
        const rate = 16000;
        const offline = new OfflineAudioContext(1, Math.max(1, Math.ceil(decoded.duration * rate)), rate);
        const source = offline.createBufferSource();
        source.buffer = decoded;
        source.connect(offline.destination);
        source.start();
        const rendered = await offline.startRendering();
        return rendered.getChannelData(0);
    } finally {
        ctx.close().catch(() => {});
    }
}

export async function transcribeBlob(blob, language) {
    if (!blob || !blob.size) return '';
    const transcriber = await loadPipeline();
    const pcm = await decodeTo16k(blob);
    if (!pcm || pcm.length < 1600) return '';
    const result = await transcriber(pcm, {
        language: language === 'en' ? 'english' : 'arabic',
        task: 'transcribe'
    });
    return String((result && result.text) || '').trim();
}

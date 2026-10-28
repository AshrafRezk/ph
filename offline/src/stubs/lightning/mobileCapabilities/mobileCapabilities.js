// The field app has no Salesforce mobile bridge; callers fall back to the browser camera.
const unavailable = {
    isAvailable: () => false,
    beginCapture: () => Promise.reject(new Error('Scanner not available')),
    endCapture: () => {},
    barcodeTypes: { QR: 'qr' }
};

export function getBarcodeScanner() {
    return unavailable;
}

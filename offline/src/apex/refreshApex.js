export async function refreshApex(wiredValue) {
    if (wiredValue && typeof wiredValue.refresh === 'function') {
        return wiredValue.refresh();
    }
    return undefined;
}

export default refreshApex;

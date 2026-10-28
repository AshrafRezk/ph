/**
 * Native-size detection for HTML decks. The player renders a deck at this
 * size and scales it to fit, so a wrong size crops the slide.
 */
import { inspectClmHtmlFiles } from 'c/clmHtmlPackage';

function hypeDeck(viewportWidth, script) {
    return [
        {
            path: 'Deck/Deck.html',
            text: `<html><head><meta name="viewport" content="user-scalable=yes, width=${viewportWidth}" /></head><body></body></html>`
        },
        { path: 'Deck/Deck.hyperesources/deck_hype_generated_script.js', text: script }
    ];
}

describe('inspectClmHtmlFiles size', () => {
    it('reads the older Hype format with Y and Z side by side', () => {
        const layout = inspectClmHtmlFiles(
            hypeDeck(1920, '{o:"3",p:"600px",a:100,Y:1920,Z:1080,b:100,cA:false}')
        );
        expect(layout).toMatchObject({ width: 1920, height: 1080 });
    });

    it('reads the newer Hype format with keys between Y and Z', () => {
        // Hype 674 export (Nexicure, Zetacolest-Plus): used to fall back to 1024x576.
        const layout = inspectClmHtmlFiles(
            hypeDeck(1024, 'G:{a:[{d:0.4,p:1,g:5,f:1}]},d:1024,cA:false,Y:1024,L:[],Z:768,v:{}')
        );
        expect(layout).toMatchObject({ width: 1024, height: 768 });
    });

    it('skips tiny Y/Z pairs that are not the scene size', () => {
        const layout = inspectClmHtmlFiles(
            hypeDeck(1024, '{Y:1,b:2,Z:180},{cA:false,Y:1024,L:[],Z:732}')
        );
        expect(layout).toMatchObject({ width: 1024, height: 732 });
    });

    it('falls back to 1920x1080 for responsive decks', () => {
        const layout = inspectClmHtmlFiles([
            {
                path: 'Zolex/index.html',
                text: '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
            }
        ]);
        expect(layout).toMatchObject({ width: 1920, height: 1080 });
    });
});

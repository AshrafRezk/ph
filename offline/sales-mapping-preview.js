import '@lwc/synthetic-shadow';
import { createElement } from 'lwc';
import DistributorsManagement from 'c/distributorsManagement';
import AdminConsole from 'c/adminConsole';

const view = new URLSearchParams(window.location.search).get('view') || 'import';
const host = document.querySelector('#app');

if (view === 'console') {
    host.appendChild(createElement('c-admin-console', { is: AdminConsole }));
} else {
    const el = createElement('c-distributors-management', { is: DistributorsManagement });
    el.initialDoctorSearch = 'Ahmed';
    host.appendChild(el);
    const openTab = () => {
        const button = host.querySelector(`[data-tab-id="${view}"]`);
        if (button) {
            button.click();
        }
    };
    setTimeout(openTab, 400);
}

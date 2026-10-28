import { LightningElement, wire } from 'lwc';
import getMyTeamTree from '@salesforce/apex/MyTeamController.getMyTeamTree';

export default class MyTeamHierarchy extends LightningElement {
    tree = [];
    expandedById = {};
    errorMessage;
    isLoading = true;

    @wire(getMyTeamTree)
    wiredTree({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.tree = data;
            this.expandedById = this.expandAll(data, {});
            this.errorMessage = undefined;
        } else if (error) {
            this.tree = [];
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load your team.';
        }
    }

    get rows() {
        return this.flatten(this.tree, 0);
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.errorMessage && !this.hasRows;
    }

    expandAll(nodes, expanded) {
        (nodes || []).forEach((node) => {
            expanded[node.territoryId] = true;
            this.expandAll(node.children, expanded);
        });
        return expanded;
    }

    flatten(nodes, depth) {
        const rows = [];
        (nodes || []).forEach((node) => {
            const users = (node.users || []).map((person) => ({
                ...person,
                key: `${node.territoryId}-${person.userId}-${person.role || ''}`
            }));
            const hasChildren = (node.children || []).length > 0;
            const expanded = this.expandedById[node.territoryId] !== false;
            rows.push({
                territoryId: node.territoryId,
                name: node.name,
                level: node.level,
                users,
                hasUsers: users.length > 0,
                hasChildren,
                expanded,
                toggleLabel: expanded ? 'Collapse' : 'Expand',
                depthStyle: `padding-left: ${depth * 1.25}rem`
            });
            if (hasChildren && expanded) {
                rows.push(...this.flatten(node.children, depth + 1));
            }
        });
        return rows;
    }

    handleToggle(event) {
        const territoryId = event.currentTarget.dataset.id;
        this.expandedById = {
            ...this.expandedById,
            [territoryId]: this.expandedById[territoryId] === false
        };
    }
}
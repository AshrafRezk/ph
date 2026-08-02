import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getAccountAffiliations from '@salesforce/apex/AccountAffiliationController.getAccountAffiliations';
import getAccountDetails from '@salesforce/apex/AccountAffiliationController.getAccountDetails';
import getRelationTypePicklistValues from '@salesforce/apex/AccountAffiliationController.getRelationTypePicklistValues';

export default class AccountAffiliationNetwork extends NavigationMixin(LightningElement) {
    _recordId;
    _dataLoadedForRecordId = null; // Track which recordId we've loaded data for
    
    @track isLoading = false;
    @track error;
    
    // SVG visualization properties
    @track svgNodes = [];
    @track svgEdges = [];
    svgWidth = 800;
    svgHeight = 600;
    animationFrameId = null;
    isRendering = false;
    clickHandlerAttached = false;
    
    // Graph data
    @track nodes = [];
    @track edges = [];
    expandedNodes = new Set();
    
    // Filters
    @track filters = {
        relationType: 'All',
        showInactive: false,
        showOutsideTerritory: true,
        strength: 'All',
        direction: 'All'
    };
    
    // Picklist values
    @track relationTypeOptions = [{ label: 'All', value: 'All' }];
    @track roleOptions = [{ label: 'All', value: 'All' }];
    @track strengthOptions = [{ label: 'All', value: 'All' }];
    @track directionOptions = [
        { label: 'All', value: 'All' },
        { label: 'Primary → Related', value: 'Primary→Related' },
        { label: 'Related → Primary', value: 'Related→Primary' }
    ];
    
    // Current account details
    @track currentAccount = null;
    
    // Form factor for mobile detection
    formFactor = FORM_FACTOR;
    
    get isMobile() {
        return this.formFactor === 'Small';
    }
    
    @api
    get recordId() {
        return this._recordId;
    }
    
    set recordId(value) {
        const oldValue = this._recordId;
        this._recordId = value;
        // When recordId is set or changes, reload data
        if (value && value !== oldValue) {
            console.log('RecordId set/changed:', value);
            this._dataLoadedForRecordId = null; // Reset flag
            this.expandedNodes.clear();
            this.expandedNodes.add(value);
            this.nodes = [];
            this.edges = [];
            if (this.network) {
                this.network.destroy();
                this.network = null;
            }
            this.loadInitialData();
        }
    }
    
    connectedCallback() {
        console.log('Component connected, recordId:', this.recordId);
        // Load data if recordId is already available
        if (this.recordId) {
            this.expandedNodes.add(this.recordId);
            this.loadInitialData();
        }
    }
    
    renderedCallback() {
        // Check if recordId is now available but data hasn't loaded
        if (this.recordId && 
            this._dataLoadedForRecordId !== this.recordId && 
            this.nodes.length === 0 && 
            !this.isLoading && 
            !this.error) {
            console.log('RecordId available in renderedCallback, loading data');
            if (!this.expandedNodes.has(this.recordId)) {
                this.expandedNodes.add(this.recordId);
            }
            this.loadInitialData();
        }
        
        // Initialize SVG visualization when data is ready
        if (this.nodes.length > 0 && this.svgNodes.length === 0) {
            this.initializeSVGVisualization();
        }
    }
    
    disconnectedCallback() {
        // Clean up animation frame
        if (this.animationFrameId) {
            cancelAnimationFrame(this.animationFrameId);
        }
    }
    
    /**
     * Load initial data
     */
    loadInitialData() {
        this.loadAccountDetails();
        // Load affiliations immediately, don't wait for library
        if (this.recordId) {
            this.loadAffiliations();
        }
    }
    
    /**
     * Wire relation type picklist values
     */
    @wire(getRelationTypePicklistValues)
    wiredRelationTypes({ error, data }) {
        if (data) {
            this.relationTypeOptions = [{ label: 'All', value: 'All' }];
            data.forEach(item => {
                this.relationTypeOptions.push({
                    label: item.label,
                    value: item.value
                });
            });
        } else if (error) {
            console.error('Error loading relation types:', error);
        }
    }
    
    /**
     * Load account details
     */
    loadAccountDetails() {
        if (!this.recordId) return;
        
        getAccountDetails({ accountId: this.recordId })
            .then(result => {
                this.currentAccount = result;
            })
            .catch(error => {
                console.error('Error loading account details:', error);
            });
    }
    
    /**
     * Load affiliations data
     */
    loadAffiliations() {
        if (!this.recordId) {
            return;
        }
        
        this.isLoading = true;
        this.error = null;
        
        const filtersJson = JSON.stringify({
            relationType: this.filters.relationType,
            showInactive: this.filters.showInactive,
            showOutsideTerritory: this.filters.showOutsideTerritory,
            direction: this.filters.direction,
            accountIds: this.expandedNodes.size > 0 ? Array.from(this.expandedNodes) : [this.recordId]
        });
        
        console.log('Loading affiliations for account:', this.recordId);
        console.log('Filters:', filtersJson);
        
        getAccountAffiliations({ 
            accountId: this.recordId, 
            filtersJson: filtersJson 
        })
        .then(result => {
            console.log('Affiliations loaded:', result);
            this._dataLoadedForRecordId = this.recordId; // Mark as loaded
            this.processGraphData(result);
            this.isLoading = false;
            // Initialize SVG visualization
            this.initializeSVGVisualization();
        })
        .catch(error => {
            this.isLoading = false;
            const errorMessage = error.body?.message || error.message || JSON.stringify(error);
            this.showError('Error loading affiliations: ' + errorMessage);
            console.error('Error loading affiliations:', error);
        });
    }
    
    /**
     * Process graph data and merge with existing nodes/edges
     */
    processGraphData(graphData) {
        // Create maps for existing nodes and edges
        const existingNodeMap = new Map();
        this.nodes.forEach(node => {
            existingNodeMap.set(node.id, node);
        });
        
        const existingEdgeMap = new Map();
        this.edges.forEach(edge => {
            const edgeKey = `${edge.from}-${edge.to}`;
            existingEdgeMap.set(edgeKey, edge);
        });
        
        // Merge new nodes
        if (graphData.nodes) {
            graphData.nodes.forEach(node => {
                if (!existingNodeMap.has(node.id)) {
                    this.nodes.push({
                        id: node.id,
                        label: node.label,
                        accountType: node.accountType,
                        isActive: node.isActive,
                        color: this.getNodeColor(node),
                        shape: 'box',
                        font: { size: 14 },
                        title: this.buildNodeTitle(node)
                    });
                }
            });
        }
        
        // Merge new edges
        if (graphData.edges) {
            graphData.edges.forEach(edge => {
                const edgeKey = `${edge.fromId}-${edge.toId}`;
                if (!existingEdgeMap.has(edgeKey)) {
                    this.edges.push({
                        id: edgeKey, // Unique ID for the edge
                        from: edge.fromId,
                        to: edge.toId,
                        label: edge.relationType || '',
                        arrows: 'to',
                        color: this.getEdgeColor(edge.relationType),
                        title: edge.description || edge.relationType || ''
                    });
                }
            });
        }
    }
    
    /**
     * Get node color based on account properties
     */
    getNodeColor(node) {
        if (node.id === this.recordId) {
            return { background: '#0176d3', border: '#014486', highlight: { background: '#014486' } };
        }
        if (!node.isActive) {
            return { background: '#c9c9c9', border: '#969696', highlight: { background: '#969696' } };
        }
        return { background: '#e3f3ff', border: '#0176d3', highlight: { background: '#0176d3' } };
    }
    
    /**
     * Get edge color based on relation type
     */
    getEdgeColor(relationType) {
        const colorMap = {
            'Parent Company': '#ff6b6b',
            'Subsidiary': '#4ecdc4',
            'Partner': '#45b7d1',
            'Supplier': '#f9ca24',
            'Customer': '#6c5ce7',
            'Distributor': '#a29bfe',
            'Affiliate': '#00b894',
            'Competitor': '#d63031',
            'Investor': '#fd79a8'
        };
        return colorMap[relationType] || '#95a5a6';
    }
    
    /**
     * Build node title for tooltip
     */
    buildNodeTitle(node) {
        let title = node.label || 'Account';
        if (node.accountType) {
            title += '\nType: ' + node.accountType;
        }
        if (node.isActive === false) {
            title += '\nStatus: Inactive';
        }
        return title;
    }
    
    /**
     * Initialize SVG-based network visualization
     */
    initializeSVGVisualization() {
        if (this.nodes.length === 0) return;
        
        // Get container dimensions
        const container = this.template.querySelector('.network-container');
        if (container) {
            const rect = container.getBoundingClientRect();
            this.svgWidth = Math.max(rect.width || 800, 800);
            this.svgHeight = Math.max(rect.height || 600, 600);
        }
        
        // Initialize node positions using force-directed layout
        this.initializeNodePositions();
        
        // Convert nodes and edges to SVG format
        this.updateSVGData();
        
        // Start animation loop for force-directed layout
        this.startForceSimulation();
    }
    
    /**
     * Initialize node positions with a simple force-directed layout
     */
    initializeNodePositions() {
        const centerX = this.svgWidth / 2;
        const centerY = this.svgHeight / 2;
        const radius = Math.min(this.svgWidth, this.svgHeight) / 3;
        
        // Initialize positions
        this.nodes.forEach((node, index) => {
            if (!node.x || !node.y) {
                if (node.id === this.recordId) {
                    // Center node at the center
                    node.x = centerX;
                    node.y = centerY;
                } else {
                    // Place other nodes in a circle
                    const angle = (index * 2 * Math.PI) / this.nodes.length;
                    node.x = centerX + radius * Math.cos(angle);
                    node.y = centerY + radius * Math.sin(angle);
                }
                node.vx = 0;
                node.vy = 0;
            }
        });
    }
    
    /**
     * Update SVG node and edge data and render
     */
    updateSVGData(forceRender = false) {
        this.svgNodes = this.nodes.map(node => ({
            id: node.id,
            label: node.label,
            x: node.x || this.svgWidth / 2,
            y: node.y || this.svgHeight / 2,
            color: node.color?.background || '#e3f3ff',
            borderColor: node.color?.border || '#0176d3',
            isPrimary: node.id === this.recordId,
            isActive: node.isActive !== false
        }));
        
        this.svgEdges = this.edges.map(edge => {
            const fromNode = this.nodes.find(n => n.id === edge.from);
            const toNode = this.nodes.find(n => n.id === edge.to);
            return {
                id: edge.id,
                from: edge.from,
                to: edge.to,
                fromX: fromNode?.x || 0,
                fromY: fromNode?.y || 0,
                toX: toNode?.x || 0,
                toY: toNode?.y || 0,
                label: edge.label,
                color: edge.color || '#848484'
            };
        });
        
        // Only render if forced or not currently animating
        if (forceRender || !this.animationFrameId) {
            this.renderSVG();
        }
    }
    
    /**
     * Update SVG element positions without re-rendering (for animation)
     */
    updateSVGPositions() {
        const svgElement = this.template.querySelector('.network-svg');
        if (!svgElement) return;
        
        // Update node positions
        this.svgNodes.forEach((node, index) => {
            const g = svgElement.querySelectorAll('g.network-node')[index];
            if (g) {
                const circle = g.querySelector('circle');
                const text = g.querySelector('text');
                if (circle) {
                    circle.setAttribute('cx', node.x);
                    circle.setAttribute('cy', node.y);
                }
                if (text) {
                    text.setAttribute('x', node.x);
                    text.setAttribute('y', node.y + 35);
                }
            }
        });
        
        // Update edge positions
        this.svgEdges.forEach((edge, index) => {
            const line = svgElement.querySelectorAll('line.network-edge')[index];
            if (line) {
                line.setAttribute('x1', edge.fromX);
                line.setAttribute('y1', edge.fromY);
                line.setAttribute('x2', edge.toX);
                line.setAttribute('y2', edge.toY);
            }
            
            const edgeText = svgElement.querySelectorAll('text.edge-label')[index];
            if (edgeText && edge.label) {
                edgeText.setAttribute('x', (edge.fromX + edge.toX) / 2);
                edgeText.setAttribute('y', (edge.fromY + edge.toY) / 2);
            }
        });
    }
    
    /**
     * Render SVG elements
     */
    renderSVG() {
        if (this.isRendering) {
            return; // Prevent concurrent renders
        }
        
        this.isRendering = true;
        const svgElement = this.template.querySelector('.network-svg');
        if (!svgElement) {
            this.isRendering = false;
            return;
        }
        
        // Set SVG dimensions
        svgElement.setAttribute('width', this.svgWidth);
        svgElement.setAttribute('height', this.svgHeight);
        
        // Clear existing content
        svgElement.innerHTML = '';
        this.clickHandlerAttached = false;
        
        // Create arrow marker
        const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
        const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker');
        marker.setAttribute('id', 'arrowhead');
        marker.setAttribute('markerWidth', '10');
        marker.setAttribute('markerHeight', '10');
        marker.setAttribute('refX', '9');
        marker.setAttribute('refY', '3');
        marker.setAttribute('orient', 'auto');
        const polygon = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
        polygon.setAttribute('points', '0 0, 10 3, 0 6');
        polygon.setAttribute('fill', '#848484');
        marker.appendChild(polygon);
        defs.appendChild(marker);
        svgElement.appendChild(defs);
        
        // Render edges
        this.svgEdges.forEach(edge => {
            const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
            line.setAttribute('x1', edge.fromX);
            line.setAttribute('y1', edge.fromY);
            line.setAttribute('x2', edge.toX);
            line.setAttribute('y2', edge.toY);
            line.setAttribute('stroke', edge.color);
            line.setAttribute('stroke-width', '2');
            line.setAttribute('marker-end', 'url(#arrowhead)');
            line.classList.add('network-edge');
            svgElement.appendChild(line);
            
            if (edge.label) {
                const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                text.setAttribute('x', (edge.fromX + edge.toX) / 2);
                text.setAttribute('y', (edge.fromY + edge.toY) / 2);
                text.setAttribute('text-anchor', 'middle');
                text.setAttribute('fill', edge.color);
                text.classList.add('edge-label', 'slds-text-body_small');
                text.textContent = edge.label;
                svgElement.appendChild(text);
            }
        });
        
        // Render nodes
        this.svgNodes.forEach(node => {
            const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            g.classList.add('network-node');
            
            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('cx', node.x);
            circle.setAttribute('cy', node.y);
            circle.setAttribute('r', node.isPrimary ? '25' : '20');
            circle.setAttribute('fill', node.color);
            circle.setAttribute('stroke', node.borderColor);
            circle.setAttribute('stroke-width', node.isPrimary ? '3' : '2');
            circle.classList.add('node-circle');
            circle.setAttribute('data-node-id', node.id);
            g.appendChild(circle);
            
            const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            text.setAttribute('x', node.x);
            text.setAttribute('y', node.y + 35);
            text.setAttribute('text-anchor', 'middle');
            text.classList.add('node-label', 'slds-text-body_small');
            text.setAttribute('data-node-id', node.id);
            text.textContent = node.label;
            g.appendChild(text);
            
            svgElement.appendChild(g);
        });
        
        // Use event delegation on the SVG element instead of individual nodes
        if (!this.clickHandlerAttached) {
            // Click handler for desktop
            svgElement.addEventListener('click', (e) => {
                const target = e.target;
                const nodeId = target.getAttribute('data-node-id');
                if (nodeId) {
                    console.log('SVG node clicked:', nodeId);
                    this.handleSVGNodeClick({ currentTarget: target });
                }
            });
            
            // Touch handlers for mobile
            let touchStartTime = 0;
            let touchStartTarget = null;
            
            svgElement.addEventListener('touchstart', (e) => {
                const target = e.target;
                const nodeId = target.getAttribute('data-node-id');
                if (nodeId) {
                    touchStartTime = Date.now();
                    touchStartTarget = target;
                    // Prevent default to avoid scrolling/zooming
                    e.preventDefault();
                }
            }, { passive: false });
            
            svgElement.addEventListener('touchend', (e) => {
                const target = e.target;
                const nodeId = target.getAttribute('data-node-id');
                const touchDuration = Date.now() - touchStartTime;
                
                // Only handle if it's a quick tap (not a long press or drag)
                if (nodeId && touchStartTarget === target && touchDuration < 300) {
                    console.log('SVG node touched:', nodeId);
                    this.handleSVGNodeClick({ currentTarget: target });
                    e.preventDefault();
                }
                
                touchStartTime = 0;
                touchStartTarget = null;
            }, { passive: false });
            
            this.clickHandlerAttached = true;
        }
        
        this.isRendering = false;
    }
    
    /**
     * Start force-directed simulation
     */
    startForceSimulation() {
        if (this.animationFrameId) {
            cancelAnimationFrame(this.animationFrameId);
        }
        
        let iterations = 0;
        const maxIterations = 300;
        
        const simulate = () => {
            if (iterations >= maxIterations) {
                this.animationFrameId = null;
                // Force final render after animation completes
                this.updateSVGData(true);
                return;
            }
            
            // Simple force-directed algorithm
            const k = Math.sqrt((this.svgWidth * this.svgHeight) / this.nodes.length);
            const repulsion = k * k;
            const attraction = k;
            
            // Reset forces
            this.nodes.forEach(node => {
                node.fx = 0;
                node.fy = 0;
            });
            
            // Repulsion between all nodes
            for (let i = 0; i < this.nodes.length; i++) {
                for (let j = i + 1; j < this.nodes.length; j++) {
                    const nodeA = this.nodes[i];
                    const nodeB = this.nodes[j];
                    const dx = nodeB.x - nodeA.x;
                    const dy = nodeB.y - nodeA.y;
                    const distance = Math.sqrt(dx * dx + dy * dy) || 1;
                    const force = repulsion / (distance * distance);
                    
                    nodeA.fx -= (dx / distance) * force * 0.1;
                    nodeA.fy -= (dy / distance) * force * 0.1;
                    nodeB.fx += (dx / distance) * force * 0.1;
                    nodeB.fy += (dy / distance) * force * 0.1;
                }
            }
            
            // Attraction along edges
            this.edges.forEach(edge => {
                const fromNode = this.nodes.find(n => n.id === edge.from);
                const toNode = this.nodes.find(n => n.id === edge.to);
                if (fromNode && toNode) {
                    const dx = toNode.x - fromNode.x;
                    const dy = toNode.y - fromNode.y;
                    const distance = Math.sqrt(dx * dx + dy * dy) || 1;
                    const force = (distance / attraction) * 0.05;
                    
                    fromNode.fx += (dx / distance) * force;
                    fromNode.fy += (dy / distance) * force;
                    toNode.fx -= (dx / distance) * force;
                    toNode.fy -= (dy / distance) * force;
                }
            });
            
            // Apply forces (with damping)
            this.nodes.forEach(node => {
                if (node.id !== this.recordId) {
                    node.vx = (node.vx || 0) * 0.9 + node.fx;
                    node.vy = (node.vy || 0) * 0.9 + node.fy;
                    node.x += node.vx;
                    node.y += node.vy;
                    
                    // Keep nodes within bounds
                    node.x = Math.max(50, Math.min(this.svgWidth - 50, node.x));
                    node.y = Math.max(50, Math.min(this.svgHeight - 50, node.y));
                }
            });
            
            iterations++;
            // Update SVG element positions directly during animation (more efficient)
            if (iterations % 3 === 0) {
                this.updateSVGPositions();
            }
            this.animationFrameId = requestAnimationFrame(simulate);
        };
        
        this.animationFrameId = requestAnimationFrame(simulate);
    }
    
    /**
     * Handle node click to expand affiliations (from list view)
     */
    handleNodeClick(event) {
        event.preventDefault();
        const nodeId = event.target.dataset.nodeId;
        if (nodeId) {
            this.handleNodeClickDirect(nodeId);
        }
    }
    
    /**
     * Handle node click directly with nodeId
     */
    handleNodeClickDirect(nodeId) {
        if (!nodeId) {
            console.log('No nodeId provided');
            return;
        }
        
        if (this.expandedNodes.has(nodeId)) {
            console.log('Node already expanded:', nodeId);
            // Allow re-expansion to refresh data
            // this.expandedNodes.delete(nodeId);
        }
        
        if (this.isLoading) {
            console.log('Already loading, skipping expansion');
            return;
        }
        
        console.log('Expanding node:', nodeId);
        this.expandedNodes.add(nodeId);
        this.loadAffiliations();
    }
    
    /**
     * Navigate to account record
     */
    navigateToAccount(accountId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                actionName: 'view'
            }
        });
    }
    
    /**
     * Handle filter changes
     */
    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        
        this.filters[field] = value;
        
        // Reset graph data when filters change
        this.nodes = [];
        this.edges = [];
        this.expandedNodes.clear();
        this.expandedNodes.add(this.recordId);
        
        this.loadAffiliations();
    }
    
    /**
     * Show error message
     */
    showError(message) {
        this.error = message;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: message,
                variant: 'error'
            })
        );
    }
    
    /**
     * Toggle filter panel
     */
    toggleFilterPanel() {
        const panel = this.template.querySelector('.filter-panel');
        if (panel) {
            panel.classList.toggle('collapsed');
        }
    }
    
    /**
     * Handle refresh button click
     */
    handleRefresh() {
        this.nodes = [];
        this.edges = [];
        this.expandedNodes.clear();
        if (this.recordId) {
            this.expandedNodes.add(this.recordId);
        }
        this.loadAffiliations();
    }
    
    get hasData() {
        return this.nodes.length > 0;
    }
    
    get hasEdges() {
        return this.edges.length > 0;
    }
    
    get nodeCount() {
        return this.nodes.length;
    }
    
    get edgeCount() {
        return this.edges.length;
    }
    
    get showSVGView() {
        // On mobile, prefer list view for better usability
        if (this.isMobile) {
            return false;
        }
        return this.svgNodes.length > 0;
    }
    
    /**
     * Handle SVG node click
     */
    handleSVGNodeClick(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        if (nodeId) {
            // Single click to expand
            this.handleNodeClickDirect(nodeId);
        }
    }
    
    /**
     * Get node label by ID
     */
    getNodeLabel(nodeId) {
        const node = this.nodes.find(n => n.id === nodeId);
        return node ? node.label : nodeId;
    }
    
    /**
     * Get edges with computed labels for template
     */
    get edgesWithLabels() {
        return this.edges.map(edge => ({
            ...edge,
            fromLabel: this.getNodeLabel(edge.from),
            toLabel: this.getNodeLabel(edge.to)
        }));
    }
}
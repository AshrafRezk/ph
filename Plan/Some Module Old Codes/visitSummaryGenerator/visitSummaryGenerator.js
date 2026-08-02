import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getVisitData from '@salesforce/apex/VisitSummaryController.getVisitData';
import formatVisitDataForAI from '@salesforce/apex/VisitSummaryController.formatVisitDataForAI';
import generateAISummary from '@salesforce/apex/VisitSummaryController.generateAISummary';
import getActivePlanCycles from '@salesforce/apex/VisitSummaryController.getActivePlanCycles';
import getAIConfig from '@salesforce/apex/VisitSummaryController.getAIConfig';

export default class VisitSummaryGenerator extends LightningElement {
    // Filter properties
    @track startDate;
    @track endDate;
    @track selectedPlanCycle = '';
    @track countedVisitsOnly = false;
    @track apiKey = '';
    
    // Data properties
    @track visits = [];
    @track summary = '';
    @track statistics = {};
    @track isLoading = false;
    @track showSummary = false;
    @track showVisitList = false;
    @track planCycleOptions = [];
    @track hasGeminiKey = true;
    @track hasChutesKey = false;
    
    // Initialize with current month
    connectedCallback() {
        const today = new Date();
        const firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
        const lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
        
        this.startDate = this.formatDateForInput(firstDay);
        this.endDate = this.formatDateForInput(lastDay);
        
        // Load visit data automatically
        this.loadVisitData();
        this.loadAIConfig();
    }
    
    // Wire active plan cycles
    @wire(getActivePlanCycles)
    wiredPlanCycles({ error, data }) {
        if (data) {
            this.planCycleOptions = [
                { label: '-- All Cycles --', value: '' },
                ...data
            ];
        } else if (error) {
            console.error('Error loading plan cycles:', error);
        }
    }
    
    // Format date for input field
    formatDateForInput(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }
    
    // Handle input changes
    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }
    
    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }
    
    handlePlanCycleChange(event) {
        this.selectedPlanCycle = event.target.value;
    }
    
    handleCountedVisitsOnlyChange(event) {
        this.countedVisitsOnly = event.target.checked;
    }
    
    handleApiKeyChange(event) {
        this.apiKey = event.target.value;
    }

    loadAIConfig() {
        getAIConfig()
            .then(config => {
                this.hasGeminiKey = config?.hasGeminiKey ?? false;
                this.hasChutesKey = config?.hasChutesKey ?? false;
            })
            .catch(error => {
                console.error('Error loading AI config:', error);
                this.hasGeminiKey = false;
                this.hasChutesKey = false;
            });
    }
    
    // Load visit data
    loadVisitData() {
        this.isLoading = true;
        this.showSummary = false;
        
        getVisitData({
            startDate: this.startDate,
            endDate: this.endDate,
            accountIds: null,
            ownerIds: null,
            planCycleId: this.selectedPlanCycle || null,
            countedVisitsOnly: this.countedVisitsOnly
        })
        .then(result => {
            if (result.success) {
                this.visits = result.visits || [];
                this.statistics = {
                    totalVisits: result.totalVisits || 0,
                    countedVisits: result.countedVisits || 0,
                    verifiedVisits: result.verifiedVisits || 0,
                    visitsWithOutcome: result.visitsWithOutcome || 0
                };
                this.showVisitList = true;
                
                this.showToast('Success', 'Visit data loaded successfully', 'success');
            } else {
                this.showToast('Error', result.message, 'error');
            }
        })
        .catch(error => {
            console.error('Error loading visit data:', error);
            this.showToast('Error', 'Failed to load visit data: ' + this.getErrorMessage(error), 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }
    
    // Generate AI summary with intelligent pre-processing for large datasets
    generateSummary() {
        if (this.visits.length === 0) {
            this.showToast('Warning', 'No visit data available to summarize', 'warning');
            return;
        }

        // If no default Gemini key and no user-provided key, block and prompt
        if (!this.hasGeminiKey && !this.hasChutesKey && !this.apiKey) {
            this.showToast('Error', 'API key not configured. Please enter a key to proceed.', 'error');
            return;
        }
        if (!this.hasGeminiKey && !this.apiKey) {
            this.showToast('Error', 'Please enter an API key to use the fallback provider.', 'error');
            return;
        }
        
        this.isLoading = true;
        this.showSummary = false;
        
        // For large datasets (>100 visits), pre-process and summarize locally first
        const smartSummary = this.createSmartSummary(this.visits);
        
        // Then call Gemini API with the pre-processed, concise summary
        generateAISummary({ visitData: smartSummary, apiKey: this.apiKey || null })
        .then(result => {
            if (result && result.success) {
                this.summary = this.formatSummaryHTML(result.summary);
                this.showSummary = true;
                
                // Wait for DOM to update before rendering
                setTimeout(() => {
                    this.renderSummary();
                }, 100);
                
                this.showToast('Success', 'Analysis generated successfully', 'success');
            } else if (result) {
                this.showToast('Error', result.message, 'error');
            }
        })
        .catch(error => {
            console.error('Error generating summary:', error);
            this.showToast('Error', 'Failed to generate summary: ' + this.getErrorMessage(error), 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }
    
    // Intelligently summarize visit data before sending to Gemini
    createSmartSummary(visits) {
        const summary = {
            period: `${this.startDate} to ${this.endDate}`,
            totalVisits: this.statistics.totalVisits,
            countedVisits: this.statistics.countedVisits,
            verifiedVisits: this.statistics.verifiedVisits,
            visitsWithOutcome: this.statistics.visitsWithOutcome,
            uniqueAccounts: new Set(),
            uniqueOwners: new Set(),
            outcomeThemes: {},
            products: {},
            competitors: {},
            issues: {},
            locations: {},
            topOutcomes: []
        };
        
        // Extract key insights from visits
        visits.forEach(visit => {
            if (visit.accountName) summary.uniqueAccounts.add(visit.accountName);
            if (visit.ownerName) summary.uniqueOwners.add(visit.ownerName);
            
            // Analyze outcomes for keywords and themes
            if (visit.outcome) {
                this.extractKeywords(visit.outcome, summary);
                
                // Keep top detailed outcomes (max 50 for context)
                if (summary.topOutcomes.length < 50) {
                    summary.topOutcomes.push({
                        account: visit.accountName,
                        date: visit.visitDate,
                        outcome: visit.outcome.substring(0, 200) // Limit length
                    });
                }
            }
        });
        
        // Convert Sets to counts
        summary.accountCount = summary.uniqueAccounts.size;
        summary.ownerCount = summary.uniqueOwners.size;
        
        // Format for AI consumption (keep under 3000 tokens ~12000 chars)
        let formatted = `=== VISIT ANALYTICS SUMMARY ===\n`;
        formatted += `Period: ${summary.period}\n`;
        formatted += `Total Visits: ${summary.totalVisits}\n`;
        formatted += `Counted Visits: ${summary.countedVisits}\n`;
        formatted += `Verified Visits: ${summary.verifiedVisits}\n`;
        formatted += `Visits with Outcomes: ${summary.visitsWithOutcome}\n`;
        formatted += `Unique Accounts: ${summary.accountCount}\n`;
        formatted += `Sales Team Members: ${summary.ownerCount}\n\n`;
        
        // Add keyword analysis
        formatted += `=== KEY THEMES & INSIGHTS ===\n`;
        formatted += this.formatTopItems(summary.products, 'Products Mentioned', 10);
        formatted += this.formatTopItems(summary.competitors, 'Competitor Activity', 10);
        formatted += this.formatTopItems(summary.issues, 'Common Issues/Feedback', 10);
        formatted += this.formatTopItems(summary.outcomeThemes, 'Outcome Themes', 15);
        
        // Add sample outcomes for context (limited)
        formatted += `\n=== SAMPLE VISIT OUTCOMES (${Math.min(summary.topOutcomes.length, 30)} of ${visits.length}) ===\n`;
        summary.topOutcomes.slice(0, 30).forEach((item, idx) => {
            formatted += `${idx + 1}. ${item.account} - ${item.outcome}\n\n`;
        });
        
        // Ensure we don't exceed ~10000 chars to avoid rate limits
        if (formatted.length > 10000) {
            formatted = formatted.substring(0, 10000) + '\n\n[Data truncated for API limits]';
        }
        
        return formatted;
    }
    
    // Extract keywords from outcome text
    extractKeywords(text, summary) {
        const lowerText = text.toLowerCase();
        
        // Product keywords (add more as needed)
        const productKeywords = ['bordlam', 'hpl', 'laminates', 'board', 'panel', 'مكسي', 'ملون', 'لامعة'];
        productKeywords.forEach(keyword => {
            if (lowerText.includes(keyword)) {
                summary.products[keyword] = (summary.products[keyword] || 0) + 1;
            }
        });
        
        // Competitor keywords
        const competitorKeywords = ['الجيل', 'cairo panel', 'el malek', 'المجد', 'competitor', 'منافس'];
        competitorKeywords.forEach(keyword => {
            if (lowerText.includes(keyword)) {
                summary.competitors[keyword] = (summary.competitors[keyword] || 0) + 1;
            }
        });
        
        // Issue/theme keywords
        const themeKeywords = {
            'price': ['price', 'سعر', 'تسعير', 'expensive', 'غالي', 'رخيص'],
            'quality': ['quality', 'جودة', 'defect', 'عيب'],
            'delivery': ['delivery', 'توصيل', 'شحن', 'تسليم', 'delay'],
            'payment': ['payment', 'دفع', 'credit', 'cash', 'فاتورة'],
            'stock': ['stock', 'مخزون', 'available', 'متوفر', 'out of stock'],
            'order': ['order', 'طلب', 'طلبية', 'أمر'],
            'distributor': ['distributor', 'موزع', 'وكيل', 'طنطا بانل', 'ريشة'],
            'interest': ['interested', 'مهتم', 'يريد', 'wants', 'needs']
        };
        
        Object.keys(themeKeywords).forEach(theme => {
            themeKeywords[theme].forEach(keyword => {
                if (lowerText.includes(keyword)) {
                    summary.outcomeThemes[theme] = (summary.outcomeThemes[theme] || 0) + 1;
                    summary.issues[keyword] = (summary.issues[keyword] || 0) + 1;
                }
            });
        });
    }
    
    // Format top items for display
    formatTopItems(items, title, limit) {
        const sorted = Object.entries(items)
            .sort((a, b) => b[1] - a[1])
            .slice(0, limit);
        
        if (sorted.length === 0) return '';
        
        let formatted = `\n${title}:\n`;
        sorted.forEach(([key, count]) => {
            formatted += `  - ${key}: ${count} mentions\n`;
        });
        
        return formatted;
    }
    
    // Test API connection - removed as it's not needed with server-side calls
    
    // Format summary from markdown-like to HTML
    formatSummaryHTML(text) {
        // Remove asterisks and format
        let formatted = text
            // Remove ** for bold (we'll use CSS for styling)
            .replace(/\*\*/g, '')
            // Remove * bullets
            .replace(/^\* /gm, '• ')
            // Add line breaks
            .replace(/\n/g, '<br/>');
        
        return formatted;
    }
    
    // Render formatted summary with special handling for Market Trends
    renderSummary() {
        const summaryDiv = this.template.querySelector('.summary-content');
        if (!summaryDiv) {
            console.warn('Summary content div not found');
            return;
        }
        
        let html = this.summary;
        
        if (!html || html.trim() === '') {
            console.warn('Summary is empty');
            summaryDiv.innerHTML = '<p>No summary available</p>';
            return;
        }
        
        // Parse sections (look for patterns like "1. EXECUTIVE SUMMARY:")
        html = html.replace(/(\d+\.\s*[A-Z\s]+:)/g, '<h2>$1</h2>');
        
        // Highlight Market Trends section with special styling
        html = html.replace(
            /((?:<h2>)?3\.\s*MARKET TRENDS:(?:<\/h2>)?)((?:.|\n)*?)(?=(?:<h2>)?\d+\.|$)/gi,
            '<div class="market-trends">$1$2</div>'
        );
        
        // Convert bullet points to list items
        const lines = html.split('<br/>');
        let inList = false;
        const result = [];
        
        lines.forEach(line => {
            const trimmedLine = line.trim();
            if (trimmedLine.startsWith('•')) {
                if (!inList) {
                    result.push('<ul>');
                    inList = true;
                }
                result.push('<li>' + trimmedLine.replace('•', '').trim() + '</li>');
            } else {
                if (inList) {
                    result.push('</ul>');
                    inList = false;
                }
                if (trimmedLine) {
                    result.push('<p>' + line + '</p>');
                }
            }
        });
        
        if (inList) {
            result.push('</ul>');
        }
        
        const finalHTML = result.join('');
        console.log('Rendering summary, length:', finalHTML.length);
        summaryDiv.innerHTML = finalHTML;
    }
    
    // Copy summary to clipboard
    copySummary() {
        // Get plain text version
        const plainText = this.summary.replace(/<[^>]*>/g, '').replace(/<br\/>/g, '\n');
        navigator.clipboard.writeText(plainText)
        .then(() => {
            this.showToast('Success', 'Summary copied to clipboard', 'success');
        })
        .catch(error => {
            console.error('Error copying to clipboard:', error);
            this.showToast('Error', 'Failed to copy to clipboard', 'error');
        });
    }
    
    // Export summary
    exportSummary() {
        const plainText = this.summary.replace(/<[^>]*>/g, '').replace(/<br\/>/g, '\n');
        const summaryText = `AI-POWERED VISIT ANALYSIS\n`;
        const header = `Period: ${this.startDate} to ${this.endDate}\n`;
        const stats = `\nSTATISTICS:\n` +
                     `Total Visits: ${this.statistics.totalVisits}\n` +
                     `Counted Visits: ${this.statistics.countedVisits}\n` +
                     `Verified Visits: ${this.statistics.verifiedVisits}\n` +
                     `Visits with Outcomes: ${this.statistics.visitsWithOutcome}\n\n`;
        const fullText = summaryText + header + stats + plainText;
        
        const element = document.createElement('a');
        element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(fullText));
        element.setAttribute('download', `Visit_Analysis_${this.startDate}_to_${this.endDate}.txt`);
        element.style.display = 'none';
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
        
        this.showToast('Success', 'Analysis exported successfully', 'success');
    }
    
    // Utility methods
    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        return 'Unknown error occurred';
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
    
    // Getters for UI
    get hasVisits() {
        return this.visits && this.visits.length > 0;
    }
    
    get statisticsText() {
        return `${this.statistics.totalVisits || 0} visits loaded (${this.statistics.countedVisits || 0} counted, ${this.statistics.visitsWithOutcome || 0} with outcomes)`;
    }
}
/// TypeScript XSLT Parser
/// Parses XSLT 1.0 templates into intermediate representation for WASM compilation.

interface XsltTemplate {
    match: string;
    instructions: XsltInstruction[];
}

type XsltInstruction =
    | { type: 'value-of'; select: string }
    | { type: 'copy-of'; select: string }
    | { type: 'text'; value: string }
    | { type: 'for-each'; select: string; children: XsltInstruction[] }
    | { type: 'if'; test: string; children: XsltInstruction[] }
    | { type: 'apply-templates'; select: string }
    | { type: 'identity' };

class XsltParser {
    private templates: XsltTemplate[] = [];
    private currentTemplate: XsltTemplate | null = null;

    parse(xsltSource: string): XsltTemplate[] {
        const lines = xsltSource.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            this.processLine(trimmed);
        }
        return this.templates;
    }

    private processLine(line: string): void {
        if (line.startsWith('<xsl:template')) {
            const match = this.extractAttribute(line, 'match') || '/';
            this.currentTemplate = { match, instructions: [] };
            this.templates.push(this.currentTemplate);
        } else if (line.startsWith('<xsl:value-of') && this.currentTemplate) {
            const select = this.extractAttribute(line, 'select') || '';
            this.currentTemplate.instructions.push({ type: 'value-of', select });
        } else if (line.startsWith('<xsl:copy-of') && this.currentTemplate) {
            const select = this.extractAttribute(line, 'select') || '';
            this.currentTemplate.instructions.push({ type: 'copy-of', select });
        } else if (line.startsWith('<xsl:for-each') && this.currentTemplate) {
            const select = this.extractAttribute(line, 'select') || '';
            this.currentTemplate.instructions.push({
                type: 'for-each', select, children: []
            });
        } else if (line.startsWith('<xsl:if') && this.currentTemplate) {
            const test = this.extractAttribute(line, 'test') || '';
            this.currentTemplate.instructions.push({
                type: 'if', test, children: []
            });
        } else if (line.startsWith('<xsl:apply-templates') && this.currentTemplate) {
            const select = this.extractAttribute(line, 'select') || '';
            this.currentTemplate.instructions.push({ type: 'apply-templates', select });
        } else if (!line.startsWith('<xsl:') && this.currentTemplate && line.length > 0) {
            this.currentTemplate.instructions.push({ type: 'text', value: line });
        }
    }

    private extractAttribute(line: string, attr: string): string | null {
        const pattern = `${attr}="`;
        const start = line.indexOf(pattern);
        if (start === -1) return null;
        const valueStart = start + pattern.length;
        const valueEnd = line.indexOf('"', valueStart);
        return line.substring(valueStart, valueEnd);
    }
}

export { XsltParser, XsltTemplate, XsltInstruction };

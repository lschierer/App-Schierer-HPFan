import * as fs from 'fs/promises';
import * as cspell from 'cspell-lib';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DEBUG = process.argv.includes('--debug');

class CSpellFixer {
  private config: cspell.CSpellSettings | undefined;

  private async loadConfig() {
    const configPath = path.join(__dirname, '..', "cspell.json");
    this.config = await cspell.loadConfig(configPath);
  }

  readonly run = async (targetDir: string) => {
    await this.loadConfig();
    
    const files = await this.getFiles(targetDir);

    for (const file of files) {
      const rawText = await fs.readFile(file, 'utf-8');
      
      // 1. Check the document
      const result = await cspell.spellCheckDocument(
        {
          uri: file,
          text: rawText,
          languageId: 'markdown',
          locale: this.config?.language || 'en',
        },
        { generateSuggestions: true },
        this.config || {}
      );

      if(DEBUG) console.log(`file ${file} has ${result.issues.length} results`);
      if (result.issues.length > 0) {
        let newText = rawText;
        // 2. Sort issues by offset DESCENDING to maintain index integrity
        const fixableIssues = result.issues
          .filter(issue => {
            if (DEBUG) console.log(`Issue "${issue.text}": hasPreferredSuggestions=${issue.hasPreferredSuggestions}, suggestions=${issue.suggestions?.length}`);
            return issue.hasPreferredSuggestions && issue.suggestions && issue.suggestions.length > 0;
          })
          .sort((a, b) => b.offset - a.offset);

        if (fixableIssues.length === 0) continue;
        if(DEBUG) console.log(`there are ${fixableIssues.length} fixable issues in file ${file}`);

        for (const issue of fixableIssues) {
          if(Array.isArray(issue.suggestions)){
            const suggestion = issue.suggestions[0];
          console.log(`Fixing "${issue.text}" -> "${suggestion}" in ${file}`);
          
          // 3. Perform the surgical replacement
          newText = 
            newText.slice(0, issue.offset) + 
            suggestion + 
            newText.slice(issue.offset + issue.text.length);  
          }
          
        }

        // 4. Write back only if changes were made
        await fs.writeFile(file, newText, 'utf-8');
      }
    }
  };

  private async getFiles(dir: string): Promise<string[]> {
    // Basic implementation; consider using 'glob' for production
    const entries = await fs.readdir(dir, { recursive: true, withFileTypes: true });
    return entries
      .filter(e => e.isFile() && e.name.endsWith('.md'))
      .map(e => path.join(e.parentPath, e.name));
  }
}

const fixer = new CSpellFixer();
await fixer.run('./share/pages');

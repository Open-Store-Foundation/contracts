#!/usr/bin/env ts-node

import * as fs from 'fs';
import * as path from 'path';

const SPDX_APACHE_2 = '// SPDX-License-Identifier: Apache-2.0';

interface ProcessResult {
  file: string;
  action: 'added' | 'updated' | 'skipped';
  reason?: string;
}

/**
 * Recursively find all .sol files in a directory
 */
function findSolFiles(dir: string): string[] {
  const files: string[] = [];
  
  const items = fs.readdirSync(dir);
  
  for (const item of items) {
    const fullPath = path.join(dir, item);
    const stat = fs.statSync(fullPath);
    
    if (stat.isDirectory()) {
      files.push(...findSolFiles(fullPath));
    } else if (item.endsWith('.sol')) {
      files.push(fullPath);
    }
  }
  
  return files;
}

/**
 * Check if file already has Apache 2.0 SPDX license
 */
function hasApacheSpdxLicense(content: string): boolean {
  return content.includes('SPDX-License-Identifier: Apache-2.0');
}

/**
 * Process a single Solidity file
 */
function processFile(filePath: string): ProcessResult {
  const content = fs.readFileSync(filePath, 'utf8');
  
  // Check if already has Apache SPDX license
  if (hasApacheSpdxLicense(content)) {
    return {
      file: filePath,
      action: 'skipped',
      reason: 'Already has Apache 2.0 SPDX license'
    };
  }
  
  let newContent: string;
  let action: 'added' | 'updated';
  
  // Check if file has any SPDX license identifier
  const spdxMatch = content.match(/^\/\/ SPDX-License-Identifier: .+$/m);
  
  if (spdxMatch) {
    // Replace existing SPDX identifier
    newContent = content.replace(
      /^\/\/ SPDX-License-Identifier: .+$/m,
      SPDX_APACHE_2
    );
    action = 'updated';
  } else {
    // Add SPDX identifier at the beginning
    if (content.trimStart().startsWith('pragma')) {
      newContent = SPDX_APACHE_2 + '\n' + content;
    } else {
      // Insert after any existing comments at the top
      const lines = content.split('\n');
      let insertIndex = 0;
      
      // Skip initial comments and empty lines
      while (insertIndex < lines.length) {
        const line = lines[insertIndex].trim();
        if (line === '' || line.startsWith('//') || line.startsWith('/*') || line.includes('*/')) {
          insertIndex++;
        } else {
          break;
        }
      }
      
      lines.splice(insertIndex, 0, SPDX_APACHE_2);
      newContent = lines.join('\n');
    }
    action = 'added';
  }
  
  // Write the updated content
  fs.writeFileSync(filePath, newContent, 'utf8');
  
  return {
    file: filePath,
    action
  };
}

/**
 * Main function
 */
function main() {
  const contractsDir = path.join(process.cwd(), 'contracts');
  
  if (!fs.existsSync(contractsDir)) {
    console.error('Error: contracts directory not found');
    process.exit(1);
  }
  
  console.log('🔍 Finding Solidity files...');
  const solFiles = findSolFiles(contractsDir);
  
  console.log(`📁 Found ${solFiles.length} Solidity files`);
  console.log('');
  
  const results: ProcessResult[] = [];
  
  for (const file of solFiles) {
    try {
      const result = processFile(file);
      results.push(result);
      
      const relativePath = path.relative(process.cwd(), file);
      const icon = result.action === 'added' ? '➕' : 
                   result.action === 'updated' ? '🔄' : '⏭️';
      
      console.log(`${icon} ${relativePath} - ${result.action}${result.reason ? ` (${result.reason})` : ''}`);
    } catch (error) {
      console.error(`❌ Error processing ${file}:`, error);
    }
  }
  
  // Summary
  console.log('');
  console.log('📊 Summary:');
  const added = results.filter(r => r.action === 'added').length;
  const updated = results.filter(r => r.action === 'updated').length;
  const skipped = results.filter(r => r.action === 'skipped').length;
  
  console.log(`  • Added SPDX licenses: ${added}`);
  console.log(`  • Updated SPDX licenses: ${updated}`);
  console.log(`  • Skipped (already correct): ${skipped}`);
  console.log(`  • Total files processed: ${results.length}`);
  
  console.log('');
  console.log('📄 Full Apache 2.0 license text is available in the LICENSE file');
  console.log('✅ SPDX license processing complete!');
}

// Run the script
if (require.main === module) {
  main();
}
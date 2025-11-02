#!/usr/bin/env node

/**
 * Create Trello Board from CSV
 *
 * Usage:
 *   node scripts/create-trello-board.js
 *
 * Prerequisites:
 *   1. Get API Key: https://trello.com/app-key
 *   2. Generate Token: Click "Token" link on that page
 *   3. Set environment variables:
 *      export TRELLO_API_KEY="your-api-key"
 *      export TRELLO_TOKEN="your-token"
 *
 * This script will:
 *   - Create a new Trello board named "CommitKit CLI Development"
 *   - Create lists (columns) for each phase
 *   - Create cards from TRELLO_BOARD.csv
 *   - Add labels to cards
 *   - Set due dates
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

// Configuration
const API_KEY = process.env.TRELLO_API_KEY;
const TOKEN = process.env.TRELLO_TOKEN;
const BOARD_ID = '2Ye3Fzgt'; // Existing board: https://trello.com/b/2Ye3Fzgt
const CSV_FILE = path.join(__dirname, '../TRELLO_BOARD.csv');

// Validate credentials
if (!API_KEY || !TOKEN) {
  console.error('❌ Missing Trello credentials');
  console.error('\nPlease set environment variables:');
  console.error('  export TRELLO_API_KEY="your-api-key"');
  console.error('  export TRELLO_TOKEN="your-token"');
  console.error('\nGet credentials at: https://trello.com/app-key');
  process.exit(1);
}

// Trello API helper
async function trelloRequest(method, endpoint, data = null) {
  const url = new URL(`https://api.trello.com/1${endpoint}`);
  url.searchParams.append('key', API_KEY);
  url.searchParams.append('token', TOKEN);

  if (method === 'GET' && data) {
    Object.entries(data).forEach(([key, value]) => {
      url.searchParams.append(key, value);
    });
  }

  const options = {
    hostname: url.hostname,
    path: url.pathname + url.search,
    method: method,
    headers: {
      'Content-Type': 'application/json',
    }
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            resolve(body);
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${body}`));
        }
      });
    });

    req.on('error', reject);

    if (method !== 'GET' && data) {
      req.write(JSON.stringify(data));
    }

    req.end();
  });
}

// Parse CSV with proper handling of quoted fields
function parseCSV(csvContent) {
  const lines = csvContent.split('\n');
  const cards = [];

  // Skip header line
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i].trim()) continue;

    // Proper CSV parsing that handles commas inside quotes
    const values = [];
    let currentValue = '';
    let insideQuotes = false;

    for (let j = 0; j < lines[i].length; j++) {
      const char = lines[i][j];

      if (char === '"') {
        insideQuotes = !insideQuotes;
      } else if (char === ',' && !insideQuotes) {
        values.push(currentValue);
        currentValue = '';
      } else {
        currentValue += char;
      }
    }
    values.push(currentValue); // Add last value

    if (values.length >= 3) {
      const card = {
        name: values[0].trim(),
        description: values[1].trim(),
        listName: values[2].trim(),
        labels: values[3] ? values[3].trim() : '',
        dueDate: values[4] ? values[4].trim() : '',
        members: values[5] ? values[5].trim() : ''
      };
      cards.push(card);
    }
  }

  return cards;
}

// Get unique list names in order
function getUniqueLists(cards) {
  const listOrder = [
    'Week 1: Core Infrastructure',
    'Week 2: Filtering & LLM',
    'Week 3: Testing',
    'Week 4: Polish & Release',
    'Backlog',
    'Post-MVP'
  ];

  const listsInData = [...new Set(cards.map(c => c.listName))];

  // Return in specified order, then any additional lists
  return [...listOrder.filter(l => listsInData.includes(l)),
          ...listsInData.filter(l => !listOrder.includes(l))];
}

// Create label color mapping
const LABEL_COLORS = {
  'MVP': 'red',
  'High Priority': 'orange',
  'Should Have': 'yellow',
  'Nice to Have': 'green',
  'Enhancement': 'blue',
  'Security': 'purple',
  'Low Priority': 'sky'
};

async function main() {
  console.log('🚀 Adding cards to Trello board from CSV...\n');

  // 1. Read and parse CSV
  console.log('📖 Reading CSV file...');
  const csvContent = fs.readFileSync(CSV_FILE, 'utf8');
  const cards = parseCSV(csvContent);
  console.log(`   Found ${cards.length} cards\n`);

  // 2. Get existing board
  console.log('📋 Getting board...');
  const board = await trelloRequest('GET', `/boards/${BOARD_ID}`);
  console.log(`   Board: ${board.name}`);
  console.log(`   URL: ${board.shortUrl}\n`);

  // 3. Create labels
  console.log('🏷️  Creating labels...');
  const labelMap = {};
  for (const [labelName, color] of Object.entries(LABEL_COLORS)) {
    const label = await trelloRequest('POST', '/labels', {
      name: labelName,
      color: color,
      idBoard: board.id
    });
    labelMap[labelName] = label.id;
    console.log(`   ✓ ${labelName} (${color})`);
  }
  console.log();

  // 4. Create lists
  console.log('📝 Creating lists...');
  const listNames = getUniqueLists(cards);
  const listMap = {};

  for (const listName of listNames) {
    const list = await trelloRequest('POST', '/lists', {
      name: listName,
      idBoard: board.id
    });
    listMap[listName] = list.id;
    console.log(`   ✓ ${listName}`);
  }
  console.log();

  // 5. Create cards
  console.log('🎴 Creating cards...');
  let cardCount = 0;

  for (const cardData of cards) {
    const cardParams = {
      name: cardData.name,
      desc: cardData.description,
      idList: listMap[cardData.listName],
      pos: 'bottom'
    };

    // Add due date if specified and valid
    if (cardData.dueDate && cardData.dueDate.trim()) {
      try {
        const dueDate = new Date(cardData.dueDate);
        if (!isNaN(dueDate.getTime())) {
          cardParams.due = dueDate.toISOString();
        }
      } catch (e) {
        // Skip invalid dates
      }
    }

    // Create card
    const card = await trelloRequest('POST', '/cards', cardParams);
    cardCount++;

    // Add labels
    if (cardData.labels && cardData.labels.trim()) {
      const labelName = cardData.labels.trim();
      if (labelMap[labelName]) {
        await trelloRequest('POST', `/cards/${card.id}/idLabels`, {
          value: labelMap[labelName]
        });
      }
    }

    // Progress indicator
    if (cardCount % 10 === 0) {
      console.log(`   Created ${cardCount}/${cards.length} cards...`);
    }
  }

  console.log(`   ✓ Created all ${cardCount} cards\n`);

  // 6. Success!
  console.log('✅ Board populated successfully!\n');
  console.log('📊 Summary:');
  console.log(`   Board: ${board.name}`);
  console.log(`   URL: ${board.shortUrl}`);
  console.log(`   Lists: ${Object.keys(listMap).length}`);
  console.log(`   Labels: ${Object.keys(labelMap).length}`);
  console.log(`   Cards: ${cardCount}`);
  console.log();
  console.log('🎉 Open your board: ' + board.shortUrl);
}

// Run script
main().catch(error => {
  console.error('❌ Error:', error.message);
  process.exit(1);
});

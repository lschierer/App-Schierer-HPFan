// AO3 Recommender SSE client — drives the <recommender-table> web component

import type { RecRow, RecommenderTable } from './recommender/RecommenderTable.js';
import './recommender/RecommenderTable.js';

async function init(): Promise<void> {
  const qs = window.__recommenderStreamQS;
  if (!qs) return;

  // Wait for the custom element to be defined
  await customElements.whenDefined('recommender-table');

  const tableEl = document.querySelector<RecommenderTable>('recommender-table');
  if (!tableEl) return;

  const url = '/Searches/Recommender/stream?' + qs;
  const es = new EventSource(url);

  es.addEventListener('progress', (e: MessageEvent) => {
    const data = JSON.parse(e.data as string) as { message: string };
    tableEl.progressMessage = data.message || 'Working…';
  });

  es.addEventListener('row', (e: MessageEvent) => {
    const rec = JSON.parse(e.data as string) as RecRow;
    console.log('recommender row event:', rec.id, rec.title);
    tableEl.upsertRow(rec);
    console.log('recommender table _data length:', tableEl._data.length);
  });

  es.addEventListener('error', (e: MessageEvent) => {
    if (e.data) {
      const data = JSON.parse(e.data as string) as { message: string };
      tableEl.addError(data.message);
    }
  });

  es.addEventListener('final', (e: MessageEvent) => {
    const results = JSON.parse(e.data as string) as RecRow[];
    tableEl.setFinalResults(results);
  });

  es.addEventListener('complete', (e: MessageEvent) => {
    const data = JSON.parse(e.data as string) as { total: number };
    tableEl.isComplete = true;
    void data;
    es.close();
  });

  es.onerror = (): void => {
    tableEl.addError('Connection to server lost. Results shown may be incomplete.');
    tableEl.isComplete = true;
    es.close();
  };
}

void init();

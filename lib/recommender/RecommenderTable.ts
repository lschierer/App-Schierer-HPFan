import { state } from 'lit/decorators.js';
import { html, css, type CSSResultGroup, nothing } from 'lit';
import { repeat } from 'lit/directives/repeat.js';

import {
  SpectrumElement,
  defineElement,
} from '@adobe/spectrum-wc-core/element/index.js';

import {
  TableController,
  flexRender,
  tableFeatures,
  createCoreRowModel,
  createSortedRowModel,
  createExpandedRowModel,
  rowSortingFeature,
  rowExpandingFeature,
  columnVisibilityFeature,
  sortFn_alphanumeric,
  sortFn_text,
  sortFn_basic,
  type ColumnDef,
  type SortingState,
  type ExpandedState,
  type HeaderContext,
} from '@tanstack/lit-table';

// The site's data-table look (header band, compact rows), shared with the Markdown, YAML and
// class-list tables. It styles `<table class="site-table">` and plain th/td beneath it, which
// is what lets it work inside this shadow root. The colour and spacing tokens it reads are
// custom properties on :root, which inherit through the shadow boundary.
import tableStyles from '../../styles/swc/table.css';

// TanStack Table v9 uses a modular feature architecture: the features you use,
// their row-model factories, and the sorting functions needed for name
// resolution (v9 no longer bundles them implicitly) are all declared statically
// via `tableFeatures()` and passed to the table through the `features` option.
const tableFeaturesConfig = tableFeatures({
  rowSortingFeature,
  rowExpandingFeature,
  columnVisibilityFeature,
  coreRowModel: createCoreRowModel(),
  sortedRowModel: createSortedRowModel(),
  expandedRowModel: createExpandedRowModel(),
  sortFns: {
    alphanumeric: sortFn_alphanumeric,
    text: sortFn_text,
    basic: sortFn_basic,
  },
});

type TableFeaturesConfig = typeof tableFeaturesConfig;

/** `aria-sort` for a header cell, given a column's sort state. */
function ariaSort(direction: false | 'asc' | 'desc'): 'ascending' | 'descending' | 'none' {
  if (direction === 'asc') return 'ascending';
  if (direction === 'desc') return 'descending';
  return 'none';
}

export interface RecRow {
  id: string;
  url: string;
  title: string;
  tags: string;
  summary: string;
  word_count: string;
  chapters: string;
  update_date: string;
  hits: string;
  kudos: string;
  score: number;
  bkmrkr_count: number;
  kdsr_count: number;
  tag_count: number;
  soft_enforced: boolean;
}

/**
 * The AO3 recommender's results table: rows arrive over a server-sent-events stream (see
 * lib/recommender.ts), sort by clicking a header, and expand to show the summary and tags.
 *
 * @element recommender-table
 */
export class RecommenderTable extends SpectrumElement {
  @state() private _sorting: SortingState = [{ id: 'score', desc: true }];
  @state() private _expanded: ExpandedState = {};
  @state() _data: RecRow[] = [];
  @state() progressMessage = 'Starting search…';
  @state() isComplete = false;
  @state() errors: string[] = [];

  private tableController = new TableController<TableFeaturesConfig, RecRow>(
    this,
  );
  private rowMap = new Map<string, RecRow>();

  static override styles: CSSResultGroup = [
    tableStyles,
    css`
      :host {
        display: block;
      }

      .recommender-progress {
        margin-bottom: 1em;
        padding: 0.5em;
        background: var(--swc-gray-100);
        border-radius: 4px;
      }

      .recommender-errors ul {
        list-style: none;
        padding: 0;
      }

      .recommender-errors li {
        color: var(--swc-negative-color-900);
        margin-bottom: 0.25em;
      }

      table {
        width: 100%;
      }

      /* The sort control is a real button, so a header can be operated from the keyboard;
         it looks like the header text it replaces. */
      .sort-button {
        padding: 0;
        border: 0;
        font: inherit;
        color: inherit;
        background: none;
        cursor: pointer;
        white-space: nowrap;
      }

      .sort-button:focus-visible,
      .expand-btn:focus-visible {
        outline: 2px solid var(--swc-link-focus-indicator-color);
        outline-offset: 2px;
      }

      th .sort-button:focus-visible {
        outline-color: var(--swc-static-white-focus-indicator-color);
      }

      .sort-indicator {
        margin-inline-start: 4px;
      }

      .expand-btn {
        padding: 2px 6px;
        border: none;
        font-size: 1em;
        color: inherit;
        background: none;
        cursor: pointer;
      }

      .detail-row td {
        padding: 8px 8px 16px 32px;
        background: var(--swc-gray-75);
        border-block-end: 1px solid var(--swc-gray-200);
      }

      .detail-summary {
        margin-bottom: 0.5em;
      }

      /* gray-700, not the lighter steps these used: it is 5.8:1 on this page's background,
         where gray-600 is 3.5:1 and fails AA for text this small. */
      .detail-score {
        font-size: 0.85em;
        color: var(--swc-gray-700);
        margin-bottom: 0.5em;
      }

      .detail-tags {
        color: var(--swc-gray-700);
        font-size: 0.9em;
      }

      a {
        color: var(--swc-link-text-color-default);
        text-decoration: none;
      }

      a:hover {
        color: var(--swc-link-text-color-hover);
        text-decoration: underline;
      }

      a:focus-visible {
        outline: 2px solid var(--swc-link-focus-indicator-color);
        outline-offset: 2px;
      }
    `,
  ];

  private columns: ColumnDef<TableFeaturesConfig, RecRow>[] = [
    {
      id: 'expander',
      enableSorting: false,
      header: () => nothing,
      cell: (info) => html`
        <button class="expand-btn" type="button"
          aria-expanded=${String(info.row.getIsExpanded())}
          aria-label="Details for ${info.row.original.title}"
          @click=${info.row.getToggleExpandedHandler()}>
          <span aria-hidden="true">${info.row.getIsExpanded() ? '▼' : '▶'}</span>
        </button>
      `,
    },
    {
      id: 'score',
      accessorFn: (row) => row.score,
      enableSorting: true,
      sortDescFirst: true,
      header: (info: HeaderContext<TableFeaturesConfig, RecRow>) =>
        this._renderHeader(info, 'Score'),
    },
    {
      id: 'title',
      accessorFn: (row) => row.title,
      enableSorting: true,
      sortDescFirst: false,
      header: (info: HeaderContext<TableFeaturesConfig, RecRow>) =>
        this._renderHeader(info, 'Title'),
      cell: (info) => {
        const row = info.row.original;
        return html`<a href="${row.url}" target="_blank" rel="noopener">${row.title}</a>`;
      },
    },
    {
      id: 'word_count',
      accessorFn: (row) => Number(row.word_count) || 0,
      enableSorting: true,
      sortDescFirst: true,
      header: (info: HeaderContext<TableFeaturesConfig, RecRow>) =>
        this._renderHeader(info, 'Words'),
      cell: (info) => info.row.original.word_count || '',
    },
    {
      id: 'chapters',
      accessorFn: (row) => row.chapters,
      enableSorting: true,
      sortDescFirst: true,
      header: (info: HeaderContext<TableFeaturesConfig, RecRow>) =>
        this._renderHeader(info, 'Chapters'),
    },
    {
      id: 'hits',
      accessorFn: (row) => Number(row.hits) || 0,
      enableSorting: true,
      sortDescFirst: true,
      header: (info: HeaderContext<TableFeaturesConfig, RecRow>) =>
        this._renderHeader(info, 'Hits'),
      cell: (info) => info.row.original.hits || '',
    },
    {
      id: 'kudos',
      accessorFn: (row) => Number(row.kudos) || 0,
      enableSorting: true,
      sortDescFirst: true,
      header: (info: HeaderContext<TableFeaturesConfig, RecRow>) =>
        this._renderHeader(info, 'Kudos'),
      cell: (info) => info.row.original.kudos || '',
    },
  ];

  private _renderHeader(
    info: HeaderContext<TableFeaturesConfig, RecRow>,
    label: string,
  ) {
    const direction = info.column.getIsSorted();
    const arrow = direction === 'asc' ? '🔼' : direction === 'desc' ? '🔽' : '';
    return html`
      <button class="sort-button" type="button"
        @click=${info.column.getToggleSortingHandler()}>
        ${label}${arrow
          ? html`<span class="sort-indicator" aria-hidden="true">${arrow}</span>`
          : ''}
      </button>
    `;
  }

  private _renderDetailRow(row: RecRow, colSpan: number) {
    const summary = row.summary.trim();
    const tags = row.tags.trim();
    return html`
      <tr class="detail-row">
        <td colspan="${colSpan}">
          <div class="detail-score">Score ${row.score}: ${row.bkmrkr_count} bookmarker, ${row.kdsr_count} kudoser, ${row.tag_count} tag</div>
          ${summary
            ? html`<div class="detail-summary">${summary}</div>`
            : nothing}
          ${tags
            ? html`<div class="detail-tags">${tags}</div>`
            : nothing}
        </td>
      </tr>
    `;
  }

  // --- Public API for the SSE driver ---

  upsertRow(rec: RecRow): void {
    this.rowMap.set(rec.id, rec);
    this._data = [...this.rowMap.values()];
  }

  setFinalResults(results: RecRow[]): void {
    this.rowMap.clear();
    for (const r of results) {
      this.rowMap.set(r.id, r);
    }
    this._data = results;
  }

  addError(msg: string): void {
    this.errors = [...this.errors, msg];
  }

  override render() {
    const table = this.tableController.table({
      features: tableFeaturesConfig,
      columns: this.columns,
      data: this._data,
      state: { sorting: this._sorting, expanded: this._expanded },
      onSortingChange: (updaterOrValue) => {
        this._sorting =
          typeof updaterOrValue === 'function'
            ? updaterOrValue(this._sorting)
            : updaterOrValue;
      },
      onExpandedChange: (updaterOrValue) => {
        this._expanded =
          typeof updaterOrValue === 'function'
            ? updaterOrValue(this._expanded)
            : updaterOrValue;
      },
      getRowCanExpand: () => true,
    });

    const colSpan = table.getAllColumns().length;

    return html`
      ${!this.isComplete
        ? html`<div class="recommender-progress">
            <p>${this.progressMessage}</p>
          </div>`
        : html`<p>Search complete.</p>`}

      ${this.errors.length > 0
        ? html`<div class="recommender-errors">
            <ul>
              ${this.errors.map((e) => html`<li>${e}</li>`)}
            </ul>
          </div>`
        : ''}

      <p>${this._data.length} recommendations</p>

      <table class="site-table">
        <thead>
          ${repeat(
            table.getHeaderGroups(),
            (hg) => hg.id,
            (hg) => html`
              <tr>
                ${repeat(
                  hg.headers,
                  (h) => h.id,
                  (h) => html`
                    <th aria-sort=${ariaSort(h.column.getIsSorted())}>
                      ${h.isPlaceholder
                        ? null
                        : flexRender(h.column.columnDef.header, h.getContext())}
                    </th>
                  `,
                )}
              </tr>
            `,
          )}
        </thead>
        <tbody>
          ${repeat(
            table.getRowModel().rows,
            (row) => row.id,
            (row) => html`
              <tr>
                ${repeat(
                  row.getVisibleCells(),
                  (cell) => cell.id,
                  (cell) => html`
                    <td>
                      ${flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  `,
                )}
              </tr>
              ${row.getIsExpanded()
                ? this._renderDetailRow(row.original, colSpan)
                : nothing}
            `,
          )}
        </tbody>
      </table>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'recommender-table': RecommenderTable;
  }
}

defineElement('recommender-table', RecommenderTable);

import { customElement, state } from 'lit/decorators.js';
import { html, css, LitElement, type CSSResultGroup, nothing } from 'lit';
import { repeat } from 'lit/directives/repeat.js';

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

import SpectrumTokensCSS from '@spectrum-css/tokens/dist/index.css' with { type: 'css' };

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

@customElement('recommender-table')
export class RecommenderTable extends LitElement {
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

  static styles: CSSResultGroup = [
    SpectrumTokensCSS,
    css`
      :host { display: block; }

      .recommender-progress {
        margin-bottom: 1em;
        padding: 0.5em;
        background: var(--spectrum-gray-100);
        border-radius: 4px;
      }

      .recommender-errors ul {
        list-style: none;
        padding: 0;
      }

      .recommender-errors li {
        color: var(--spectrum-negative-color-900, #c00);
        margin-bottom: 0.25em;
      }

      table {
        width: 100%;
        border-collapse: collapse;
      }

      th {
        cursor: pointer;
        user-select: none;
        text-align: left;
        padding: 8px;
        border-bottom: 2px solid var(--spectrum-gray-300);
        white-space: nowrap;
      }

      td {
        padding: 8px;
        border-bottom: 1px solid var(--spectrum-gray-200);
        vertical-align: top;
      }

      .sort-indicator { margin-left: 4px; }

      .expand-btn {
        cursor: pointer;
        background: none;
        border: none;
        font-size: 1em;
        padding: 2px 6px;
      }

      .detail-row td {
        padding: 8px 8px 16px 32px;
        background: var(--spectrum-gray-75, #fafafa);
        border-bottom: 1px solid var(--spectrum-gray-200);
      }

      .detail-summary {
        margin-bottom: 0.5em;
      }

      .detail-score {
        font-size: 0.85em;
        color: var(--spectrum-gray-600, #888);
        margin-bottom: 0.5em;
      }

      .detail-tags {
        color: var(--spectrum-gray-700, #666);
        font-size: 0.9em;
      }

      a {
        color: var(--spectrum-accent-color-900);
        text-decoration: none;
      }
      a:hover { text-decoration: underline; }
    `,
  ];

  private columns: ColumnDef<TableFeaturesConfig, RecRow>[] = [
    {
      id: 'expander',
      enableSorting: false,
      header: () => nothing,
      cell: (info) => html`
        <button class="expand-btn"
          @click=${info.row.getToggleExpandedHandler()}>
          ${info.row.getIsExpanded() ? '▼' : '▶'}
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
      <div @click=${info.column.getToggleSortingHandler()}>
        ${label}${arrow
          ? html`<span class="sort-indicator">${arrow}</span>`
          : ''}
      </div>
    `;
  }

  private _renderDetailRow(row: RecRow, colSpan: number) {
    const summary = row.summary?.trim();
    const tags = row.tags?.trim();
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
    this.rowMap.set(String(rec.id), rec);
    this._data = [...this.rowMap.values()];
  }

  setFinalResults(results: RecRow[]): void {
    this.rowMap.clear();
    for (const r of results) {
      this.rowMap.set(String(r.id), r);
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

      <table>
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
                    <th @click=${h.column.getToggleSortingHandler()}>
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

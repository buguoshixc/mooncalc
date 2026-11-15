// Minimal RFC-4180-ish CSV parser: quoted fields, "" escapes, CRLF tolerant,
// leading BOM stripped, unterminated quoted fields rejected.
// Zero dependencies; imported by app.js (drag-drop import) and smoke.html.
export function parseCsv(text) {
  if (text[0] === '\uFEFF') text = text.slice(1);
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  let i = 0;
  const pushField = () => { row.push(field); field = ''; };
  const pushRow = () => { pushField(); rows.push(row); row = []; };
  while (i < text.length) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
        inQuotes = false; i++; continue;
      }
      field += ch; i++; continue;
    }
    if (ch === '"') { inQuotes = true; i++; continue; }
    if (ch === ',') { pushField(); i++; continue; }
    if (ch === '\r') { i++; continue; }
    if (ch === '\n') { pushRow(); i++; continue; }
    field += ch; i++;
  }
  if (inQuotes) throw new Error('unterminated quoted field');
  if (field !== '' || row.length) pushRow();
  if (rows.length && rows[rows.length - 1].length === 1 && rows[rows.length - 1][0] === '') rows.pop();
  return rows;
}

pub fn __init() void {
    return struct { fn anon() V {
        var M = .{};
        var F_BODY = "\\f,14";
        var F_H1 = "\\f,22\\b";
        var F_H2 = "\\f,18\\b";
        var F_H3 = "\\f,15\\b";
        var F_QUOTE = "\\f,13\\i";
        var F_CITE = "\\f,11\\i";
        var F_VERB = "\\f,13\\b";
        var F_NOTE = "\\f,12\\i";
        var F_FILE = "\\f,12\\b";
        var F_FOOT = "\\f,11\\i";
        var NL = "\\n\\r";
        var NL2 = NL ++ NL;
        var OFF_B = "\\!b";
        var OFF_I = "\\!i";
        const esc = struct { fn esc(s: Obj) V {
            if (!s) {
                return "";
            }
            s = tostring(s);
            s = s.gsub("\\", "\\\\");
            return s;
        } }.esc;

        var WRAP_W = 100;
        const wrap = struct { fn wrap(s: Obj, max_chars: anytype) V {
            if (!s) {
                return "";
            }
            s = tostring(s);
            max_chars = max_chars or WRAP_W;
            var out = .{};
            var line = .{};
            var cur = 0;
            const emit_word = struct { fn emit_word(w: Obj) void {
                var wlen = @intCast(w.len);
                while (wlen > max_chars) {
                    if (cur > 0) {
                        table.insert(out, table.concat(line, " "));
                        line = .{};
                        cur = 0;
                    }
                    table.insert(out, w.sub(1, max_chars));
                    w = w.sub(max_chars + 1);
                    wlen = @intCast(w.len);
                }
                if ((cur > 0) and ((cur + 1 + wlen) > max_chars)) {
                    table.insert(out, table.concat(line, " "));
                    line = .{};
                    cur = 0;
                }
                if (wlen > 0) {
                    table.insert(line, w);
                    cur = cur + (((cur > 0) and 1) or 0) + wlen;
                }
            } }.emit_word;
            for (s.gmatch("%S+")) |__may_pair| {
                const word = __may_pair[0];
                emit_word(word);
            }
            if (@intCast(line.len) > 0) {
                table.insert(out, table.concat(line, " "));
            }
            return table.concat(out, NL);
        } }.wrap;

        const render_block = struct { fn render_block(b: anytype, idx_per_kind: anytype) []const u8 {
            if (b.kind == "text") {
                return F_BODY ++ (esc(wrap(b.body)) ++ NL2);
            } else if (b.kind == "h2") {
                return F_H2 ++ (esc(b.body) ++ (OFF_B ++ NL2));
            } else if (b.kind == "h3") {
                return F_H3 ++ (esc(b.body) ++ (OFF_B ++ NL2));
            } else if (b.kind == "epigraph") {
                return F_QUOTE ++ ("  " ++ (esc(wrap(b.body, 96)) ++ (OFF_I ++ (NL ++ (F_CITE ++ ("      — " ++ (esc(b.cite) ++ (OFF_I ++ NL2))))))));
            } else if (b.kind == "quote") {
                return F_QUOTE ++ ("  > " ++ (esc(wrap(b.body, 96)) ++ (OFF_I ++ (NL ++ (F_CITE ++ ("      — " ++ (esc(b.cite) ++ (OFF_I ++ NL2))))))));
            } else if (b.kind == "code") {
                return F_BODY ++ ("  " ++ (__may_method(esc(b.body).gsub, "\n", NL ++ "  ") ++ NL2));
            } else if (b.kind == "verbbox") {
                var n = idx_per_kind.verbbox;
                var label = string.format("[%d] ▶ ", n);
                var note = (b.note and (NL ++ (F_NOTE ++ ("    " ++ (esc(wrap(b.note, 92)) ++ OFF_I))))) or "";
                return F_VERB ++ (label ++ (esc(wrap(b.chain, 92)) ++ (OFF_B ++ (note ++ NL2))));
            } else if (b.kind == "fileref") {
                var n = idx_per_kind.fileref;
                var label = string.format("[f%d] → ", n);
                var note = (b.note and ("  " ++ (F_NOTE ++ (esc(wrap(b.note, 92)) ++ OFF_I)))) or "";
                return F_FILE ++ (label ++ (esc(wrap(b.path, 92)) ++ (OFF_B ++ (note ++ NL2))));
            } else if (b.kind == "articleref") {
                var n = idx_per_kind.articleref;
                var label = string.format("[a%d] → article: ", n);
                return F_FILE ++ (label ++ (esc(b.title or b.slug) ++ (OFF_B ++ NL2)));
            } else if (b.kind == "ticketref") {
                var n = idx_per_kind.ticketref;
                var label = string.format("[t%d] → ticket: ", n);
                var note = (b.note and ("  " ++ (F_NOTE ++ (esc(wrap(b.note, 92)) ++ OFF_I)))) or "";
                return F_FILE ++ (label ++ (esc(b.id) ++ (OFF_B ++ (note ++ NL2))));
            } else if (b.kind == "crosslink") {
                return F_FILE ++ ("  → " ++ (esc(b.target) ++ (OFF_B ++ NL2)));
            } else if (b.kind == "bridge") {
                return F_QUOTE ++ ("  " ++ (esc(wrap(b.body, 96)) ++ (OFF_I ++ NL2)));
            } else if (b.kind == "rule") {
                return F_BODY ++ ("  " ++ ("────" ++ ("────" ++ NL2)));
            }
            return "";
        } }.render_block;

        const lint_visibility = struct { fn lint_visibility(view: anytype) bool {
            for (view.body or .{}, 0..) |b, _| {
                if (b.kind == "verbbox") {
                    return true;
                }
            }
            return false;
        } }.lint_visibility;

        M.render_view = struct { fn anon(view: anytype, entry: anytype, idx: anytype, total: anytype) V {
            var out = .{};
            var title = view.title or (entry and entry.title) or "untitled";
            var subt = view.subtitle or "";
            var pos = string.format("  %d / %d", idx, total);
            table.insert(out, F_H1 ++ (esc(title) ++ (OFF_B ++ NL)));
            if (subt and (subt != "")) {
                table.insert(out, F_NOTE ++ (esc(subt) ++ (OFF_I ++ NL)));
            }
            table.insert(out, F_NOTE ++ (esc(pos) ++ (OFF_I ++ NL2)));
            if (view.cross_links and (@intCast(view.cross_links.len) > 0)) {
                table.insert(out, F_NOTE ++ ("  see also: " ++ OFF_I));
                for (view.cross_links, 0..) |target, i| {
                    var sep = ((i > 1) and "  ·  ") or "";
                    table.insert(out, F_FILE ++ (sep ++ (esc(target) ++ OFF_B)));
                }
                table.insert(out, NL2);
            }
            if (!lint_visibility(view)) {
                table.insert(out, F_VERB ++ ("[ MISSING-VERBBOX ribbon: this view declares no verb ]" ++ (OFF_B ++ NL2)));
            }
            var idx_per_kind = .{
                .verbbox = 0,
                .fileref = 0,
                .articleref = 0,
                .ticketref = 0,
            };
            for (view.body or .{}, 0..) |b, _| {
                if (idx_per_kind[b.kind] != null) {
                    idx_per_kind[b.kind] = idx_per_kind[b.kind] + 1;
                }
                table.insert(out, render_block(b, idx_per_kind));
            }
            if (view.tickets and (@intCast(view.tickets.len) > 0)) {
                table.insert(out, NL ++ (F_H2 ++ ("References" ++ (OFF_B ++ NL2))));
                for (view.tickets, 0..) |tid, _| {
                    table.insert(out, F_FILE ++ ("  → " ++ (esc(tid) ++ (OFF_B ++ NL))));
                }
                table.insert(out, NL);
            }
            table.insert(out, NL2 ++ (F_FOOT ++ ("  h: home    p / n: prev / next    j / k: scroll    " ++ ("ESC: quit" ++ (OFF_I ++ NL)))));
            table.insert(out, F_FOOT ++ ("  CC-BY 3.0: epigraph quotes from Mellstrand & Ståhl, " ++ ("Systemic Software Debugging (2012)." ++ (OFF_I ++ NL))));
            return table.concat(out);
        } }.anon;

        M.render_index = struct { fn anon(catalogue: anytype) V {
            var out = .{};
            table.insert(out, F_H1 ++ ("sysdebug" ++ (OFF_B ++ NL)));
            table.insert(out, F_NOTE ++ ("  the canonical companion to *Systemic Software Debugging*, " ++ ("applied to the arcan / hem / zig stack" ++ (OFF_I ++ NL2))));
            for (catalogue, 0..) |entry, i| {
                var label = string.format("  [%d]  %s", i, entry.title);
                if (entry.date) {
                    label = label ++ ("   (" ++ (entry.date ++ ")"));
                }
                table.insert(out, F_BODY ++ (esc(label) ++ NL));
            }
            table.insert(out, NL ++ (F_FOOT ++ ("  press digit to open;  h returns here;  ESC quits" ++ (OFF_I ++ NL))));
            return table.concat(out);
        } }.anon;

        return M;
    } }.anon;
}

-- paste <file> <base64-payload>
--
-- Decode base64 payload into bytes, write to file. Companion to
-- `write` (which only accepts cmdline string args or job refs);
-- `paste` accepts a single base64 token, surviving cat9's chain
-- tokenizer because the base64 alphabet has no quote/paren/space
-- chars — so multi-line content with arbitrary special chars can
-- finally reach a `|||`-separated chain segment as a single arg.
--
-- Accepts both standard (+ /) and url-safe (- _) base64 alphabets;
-- padding `=` is optional. The tokenizer otherwise strips
-- whitespace and `\r\n` so wrapped payloads work too.
--
-- Visual: small cell with a one-line summary "paste N bytes
-- decoded from M b64 chars to <file>". Registered in dev_helpers
-- edits tracker so `edits` cell shows it.
--
-- Why this exists: see ticket 0155 (cat9-multiline-write) — without it, multi-line source
-- code (Zig with parens, TS with quotes, etc.) cannot be fed
-- through cat9 chains, so any visible-only workflow falls back to
-- harness Write or shell `cp` from a staged file. With paste,
-- agents base64-encode content client-side and ship it through
-- one chain segment — fully cat9-visible end-to-end.

local function b64decode(s)
    local alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local lookup = {}
    for i = 1, #alphabet do
        lookup[alphabet:sub(i, i)] = i - 1
    end
    -- standard alphabet
    lookup["+"] = 62
    lookup["/"] = 63
    -- url-safe alphabet
    lookup["-"] = 62
    lookup["_"] = 63

    -- Strip whitespace and CR/LF that may sneak in via wrapped payloads.
    s = s:gsub("[%s\r\n]", "")

    local out = {}
    local bits = 0
    local nbits = 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "=" then break end
        local v = lookup[c]
        if v == nil then
            return nil, "invalid base64 char at offset " .. tostring(i)
        end
        bits = bits * 64 + v
        nbits = nbits + 6
        if nbits >= 8 then
            nbits = nbits - 8
            local byte = math.floor(bits / (2 ^ nbits))
            bits = bits % (2 ^ nbits)
            table.insert(out, string.char(byte))
        end
    end
    return table.concat(out)
end

return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.paste =
    "Write base64-decoded payload to file. Usage: paste <file> <base64>"

function suggest.paste(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.paste(path, payload)
    if not path or not payload then
        cat9.add_message("paste >file< <base64>")
        H.emit_result("paste:err:reason=missing_args")
        return
    end

    if type(payload) ~= "string" then
        cat9.add_message("paste: payload must be a string token")
        H.emit_result("paste:err:reason=non_string_payload")
        return
    end

    local content, derr = b64decode(payload)
    if not content then
        cat9.add_message("paste: " .. tostring(derr))
        H.emit_result(string.format("paste:err:path=%s:reason=%s",
            path, tostring(derr)))
        return
    end

    local bytes, werr = H.write_file(path, content)
    if not bytes then
        cat9.add_message("paste: " .. tostring(werr))
        H.emit_result(string.format("paste:err:path=%s:reason=%s",
            path, tostring(werr)))
        return
    end

    H.register_edit(path, "paste")

    local data = {linecount = 1, bytecount = 0}
    local summary = string.format(
        "paste %d bytes decoded from %d b64 chars to %s",
        bytes, #payload, path)
    table.insert(data, summary)
    data.bytecount = #summary

    cat9.import_job({
        short = "paste " .. path,
        raw = "paste " .. path,
        data = data,
        exit = 0,
    })
    cat9.flag_dirty()
    H.emit_result(string.format(
        "paste:ok:path=%s:bytes=%d:b64_len=%d",
        path, bytes, #payload))
end

end

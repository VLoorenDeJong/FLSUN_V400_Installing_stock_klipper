print_status "Updating [mcu] serial in printer.cfg..."

# Find the line number of the [mcu] section
MCU_START=$(grep -n "^

\[mcu\]

" "$PRINTER_CFG" | cut -d: -f1 || true)

if [ -z "$MCU_START" ]; then
    print_warning "[mcu] section not found, appending new section..."
    {
        echo ""
        echo "[mcu]"
        echo "serial: $MCU_SERIAL"
    } >> "$PRINTER_CFG"
    print_success "Appended new [mcu] section with serial"
else
    # Find next section header after [mcu]
    MCU_END=$(awk "NR>$MCU_START && /^

\[.*\]

/ {print NR; exit}" "$PRINTER_CFG")

    # If no next section, use end of file
    [ -z "$MCU_END" ] && MCU_END=$(wc -l < "$PRINTER_CFG")

    # Check if serial line exists inside the block
    if sed -n "${MCU_START},${MCU_END}p" "$PRINTER_CFG" | grep -q "^serial:"; then
        print_status "Replacing existing serial line..."
        sed -i "${MCU_START},${MCU_END}s|^serial:.*|serial: $MCU_SERIAL|" "$PRINTER_CFG"
    else
        print_status "Adding missing serial line to [mcu] block..."
        sed -i "$((MCU_START+1))i serial: $MCU_SERIAL" "$PRINTER_CFG"
    fi

    print_success "Updated [mcu] serial in printer.cfg"
fi

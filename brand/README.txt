ModRunner — Markenpaket
=======================

Marke: Fibonacci-VU. Sechs Balken im Höhenverhältnis 1 : 2 : 3 : 5 : 8 : 13,
jeder Balken in genau so viele Segmente geteilt.

Farben
------
Orange   #FF6B35   Primär
Lachs    #FFA997   Sekundär
Blau     #3B67A2   Akzent
Dunkel   #17130F   Hintergrund dunkel
Hell     #EDE6E0   Hintergrund hell

Lachs ist das Primärorange, aufgehellt und entsättigt: dieselbe Farbe, aber
so weit zurückgenommen, dass sie auf dunklem Grund und in kleinen Flächen
lesbar bleibt, wo das reine Orange zu laut wird. Blau liegt dem Orange auf
dem Farbkreis annähernd gegenüber und ist der kühle Gegenpol dazu; es trägt
alles, was ruhig bleiben soll. Die fünf Werte sind gesetzt und werden nicht
nachgerechnet — die Bildmarke ist an ihnen ausgerichtet.

Wortmarke: Space Grotesk Bold, Laufweite -0.035em, "Runner" in Orange.
Die Wortmarke steht in einer Zeile mit der Bildmarke, Unterkante bündig
mit der Balkenbasis.

Inhalt
------
svg/       mark.svg (transparent), icon-dark.svg, icon-light.svg — vektoriell, frei skalierbar
png/       icon-1024-dark.png, icon-1024-light.png, mark-1024-transparent.png,
           lockup-dark.png, lockup-light.png (Bild- + Wortmarke, 2x)
macos/     ModRunner.icns sowie ModRunner.iconset/ mit allen Standardgrößen
windows/   ModRunner.ico (16–256 px, 32 bit) und PNG-Fallbacks
linux/     hicolor/<größe>/apps/modrunner.png nach Freedesktop-Icon-Theme-Spezifikation

Hinweise
--------
macOS: die @2x-Dateien im iconset wurden beim Export als "-2x" abgelegt.
Vor dem Neubau der .icns umbenennen:

    cd macos/ModRunner.iconset
    for f in *-2x.png; do mv "$f" "${f%-2x.png}@2x.png"; done
    cd .. && iconutil -c icns ModRunner.iconset

Die mitgelieferte ModRunner.icns ist bereits fertig und braucht diesen
Schritt nicht.

Linux: Dateien nach ~/.local/share/icons/hicolor/ oder
/usr/share/icons/hicolor/ kopieren, dann `gtk-update-icon-cache`.

Ab 32 px abwärts werden die Balken massiv statt segmentiert gezeichnet,
damit die Marke lesbar bleibt.

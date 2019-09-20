# Flugbuch.jl

Dieses Programm ist ein Kommandozeilenprogramm, das in der interaktiven [Julia](https://julialang.org/)-Shell (REPL) läuft. Zur Verwendung muss also der Julia-Interpreter installiert sein.

Die Flugbuchdaten können direkt aus Vereinsflieger per CSV-Import eingelesen werden und sind dann in einer SQLite-Datenbank gesichert. Einerseits kann auf dieser Datenbank dann per SQL operiert werden, andererseits kann *Flugbuch.jl* die Daten dann auch übersichtlich in Tabellen auf der Konsole ausgeben. Dabei können verschiedene Filter angewendet werden und Schulungsflüge von Fluglehrern werden dabei automatisch gruppiert, sofern sie die Kriterien dafür erfüllen (gleicher PIC, gleiches Luftfahrtzeug und nicht mehr als 30 Minuten auseinander).

Leider ist Julia zum jetzigen Zeitpunkt nur bedingt für derartige Programme geeignet, sodass die Ausführungsgeschwindigkeit nach dem Starten des Programms erstmal ein wenig zu wünschen übrig lässt (wegen Just-In-Time-Compilierung). Steht zu hoffen, dass sich die Situation hier mit der Weiterentwicklung der Programmiersprache Julia deutlich verbessert. Das vorliegende Projekt war und ist jedenfalls auch ein Spielprojekt zum Kennenlernen der Programmiersprache.

## Installation

Zunächst muss Julia installiert werden und die interaktive Shell gestartet werden.

In der Julia-Shell kann *Flugbuch.jl* wie folgt installiert werden:
```julia
import Pkg
Pkg.add(Pkg.PackageSpec(url="https://github.com/julianschick/flugbuch.git"))
```
## Benutzung

In der Julia-Shell die Sitzung stets beginnen mit

```julia
using Flugbuch
```
Anschließend kann z. B. ein Flugbuch erstellt werden:
```julia
create("flugbuch.db")
```
Weitere Kommandos sind in der Hilfe aufgelistet:
```julia
help()
```
In der Datei `~/.flugbuchrc` sollte zumindest der Name des Piloten abgelegt sein:
```ini
;
; Flugbuch-Konfigurationsdatei
;

defaultdb=/home/mustermann/flugbuch/flugbuch.db
mynames=Mustermann, Martha; Martha Mustermann
```
Darüber hinaus kann ein Standardflugbuch angegeben werden, dass dann mit `load()` ohne die Angabe einer Datei geladen werden kann.


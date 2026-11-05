javac -J-Duser.language=en -J-Duser.country=US -d out src/Bad.java
tool version: javac 25 (Corretto 25.0.0.36.2)
2026-11-04
^(?P<file>[^:\s][^:]*\.java):(?P<line>\d+): (?P<severity>error|warning): (?P<message>.*)$

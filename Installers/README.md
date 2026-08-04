# Instaladores

Acá se acumulan **todas las versiones** del instalador (`.dmg`) de Termacos SSH.
`./make_dmg.sh` copia cada build nueva a esta carpeta — nunca borra las
anteriores, así que queda un historial completo para poder instalar cualquier
versión en otra Mac.

## Cómo generar una nueva versión

1. Editá el archivo `VERSION` en la raíz del repo (ej. `1.0` → `1.1`).
2. Corré `./make_dmg.sh` desde la raíz del repo.
3. El nuevo `TermacosSSH-<version>.dmg` aparece acá junto a los anteriores.

Si volvés a correr `make_dmg.sh` sin cambiar `VERSION`, se sobrescribe el
`.dmg` de esa misma versión (es un rebuild, no una versión nueva).

## Instalar en otra Mac

Copiá el `.dmg` de la versión que quieras a la otra Mac, abrilo y arrastrá
"Termacos SSH.app" a Applications.

#!/bin/bash
# Esperar a que el escritorio esté listo
sleep 5

# Exportar la pantalla gráfica
export DISPLAY=:0

# Bucle infinito para que nunca muera y se relance si se cierra o la actualizan
while true; do
    /home/sdimp/broker/linux-aarch64/Broker
    sleep 5
done

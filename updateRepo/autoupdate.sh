#!/bin/bash

# Ruta a la carpeta de tu proyecto en la Raspberry Pi
REPO_DIR="/home/sdimp/broker/"
APP_DIR="/home/sdimp/broker/linux-aarch64"
# Nombre de la aplicacion
APP_NAME="Broker"
# entrarmos a la carpeta
cd "$REPO_DIR" || exit
# Cerramos la aplicacion para tomar cambios
sudo pkill -f "$APP_NAME"
sleep 2
# Actualizamos el repositorio
git pull origin main
sync
echo "El repositorio ya está actualizado."

cd "$APP_DIR" || exit
export DISPLAY=:0
export XAUTHORITY=/home/sdimp/.Xauthority
nohup ./Broker > /home/sdimp/broker/broker.log 2>&1 &
# ./Broker
#export XAUTHORITY=/home/sdimp/.Xauthority
#nohup /home/sdimp/broker/linux-aarch64/Broker > /home/sdimp/broker/broker.log 2>&1 &

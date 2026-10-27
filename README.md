# Guía de Instalación y Configuración en Linux / Raspberry Pi

## 1. Actualización inicial del sistema

Antes de instalar cualquier paquete, actualiza la lista de repositorios e índice de paquetes del sistema operativo:

```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Instalación de Herramientas Básicas

### Instalar Git
Git te permitirá clonar y sincronizar tu proyecto directamente desde repositorios remotos (GitHub).

```bash
# Instalación de Git
sudo apt install -y git

# Verificar instalación
git --version

# Configuración básica global
git config --global user.name "Tu Nombre o Usuario"
git config --global user.email "tu_correo@ejemplo.com"
```

### Instalar Java (JRE)
Necesario para ejecutar la aplicación exportada desde Processing en el sistema operativo.

```bash
# Instalación del entorno de ejecución de Java
sudo apt install -y default-jre

# Verificar que Java está correctamente instalado
java -version
```

### Instalar y Activar Tailscale
Permite conectar la Raspberry Pi a tu red privada virtual evitando bloqueos de firewall y restricciones de puertos SSH.

```bash
# Script oficial de instalación
curl -fsSL https://tailscale.com/install.sh | sh

# Iniciar el servicio y autenticar el dispositivo
sudo tailscale up
```
**Nota:** 
- Copia la URL que aparece en la terminal (`https://login.tailscale.com/a/...`), ábrela en un navegador y autoriza el dispositivo.
- Se deben autorizar en ambos equipos, computador y raspberry

```bash
# Verificar estado y obtener la IP asignada (100.x.x.x)
tailscale status
```

## 3. Configuración de Carpeta del Proyecto y Sincronización (Git Pull)

### Estructura de Directorio
Ruta (`/home/sdimp/broker/`).

### Creamos clave ssh para conectar al repositorio
En terminal de la raspberry ejecutar
```bash
ssh-keygen -t ed25519 -C "richardtabaresb@gmail.com"
```
Presiona Enter a todo para dejar las opciones por defecto

### Copiamos la clave en la ruta que nos da
cat ~/.ssh/id_ed25519.pub (ejemplo)

### Agregar la clave a tu cuenta de GitHub
- Ve a GitHub > Settings > SSH and GPG keys.
- Haz clic en New SSH key.
- Pega la clave y guárdala.

**Nota** Usar enlace de ssh para github en lugar de https

### Crear e ir al directorio broker
```bash
mkdir broker
cd broker
```

### Inicializamos git
```bash
git init
```

### Creamos el remoto a github
```bash
git remote add origin git@github.com:richard-tabares/sdimp_broker.git
```

### Configuramos para que solo sincronice la carpeta especifica de la aplicacion
```bash
git config core.sparseCheckout true
echo "linux-aarch64/" >> .git/info/sparse-checkout
```

### Sincronizamos aplicacion con el remoto
```bash
git pull origin main
```
### Comando para actualizar el proyecto
Cada vez que subas cambios desde tu PC a GitHub, actualiza la Raspberry Pi ejecutando:

```bash
cd ~/broker
git pull origin main
```

## 4. Configurar Inicio Automático al Encender la Raspberry Pi y script de actualización
Para que la aplicacion java se lance al arrancar el entorno gráfico:

1. Edita o crea el archivo de autostart del escritorio:
```bash
sudo nano /etc/xdg/autostart/display.desktop
```
2. Añade la siguiente configuracion para el broker
```ini
[Desktop Entry]
Exec=/home/sdimp/broker/linux-aarch64/Broker
```
3. Guarda y cierra (`Ctrl + O`, `Enter`, `Ctrl + X`).

## 5. Configurar archivo conf.txt /home/sdimp/broker/linux-aarch64/data/conf.txt
- Empresa: nombre de la mina
- Mina: nombre de la mina
- Direccion: (IP del cliente broker)
- Equipos: numero de equipos que va soportar el broker
- TimeoutConexion: configurar milisegundos de cada estacion antes de ponerlas en rojo (por defecto 20000)

## 6. Verificación de Conexión Remota (SSH vía Tailscale)

Desde tu laptop/PC conectada a la misma red de Tailscale:

```bash
ssh sdimp@<IP-TAILSCALE-RASPBERRY>
```
*(Ejemplo: `ssh sdimp@100.x.x.x` o `ssh sdimp@raspberrypi`).*
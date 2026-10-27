#!/usr/bin/env python3
"""Simulador de equipos (estaciones) para el Broker SDIMP.

Replica el envio del equipo real:

    id CO2 CO H2S NO2 O2 anio mes dia hora min seg\\n

Envia una trama cada 2 segundos por equipo, sin esperar ACK. Los ACK del
broker se drenan y se cuentan solo como diagnostico.

Ejemplos:
    python3 sim_tramas.py --equipos 15
    python3 sim_tramas.py --equipos 15 --escenario alarma,desconexion
    python3 sim_tramas.py --equipos 1 --formato fijo --verbose
"""

import argparse
import json
import os
import random
import signal
import socket
import threading
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONF_BROKER = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "data", "conf.txt"))
CONFIG_SIM = os.path.normpath(os.path.join(SCRIPT_DIR, "sim_config.json"))

GASES = ["CO2", "CO", "H2S", "NO2", "O2"]
DECIMALES = {"CO2": 2, "CO": 1, "H2S": 2, "NO2": 2, "O2": 1}
ZONA_ALARMA = {
    "CO2": (1.0, 5.0),
    "CO": (25.0, 200.0),
    "H2S": (1.0, 50.0),
    "NO2": (0.2, 20.0),
}
O2_ALARMA_BAJA = (17.0, 19.4)
O2_ALARMA_ALTA = (23.6, 25.0)

DEFAULTS = {
    "host": "127.0.0.1",
    "puerto": 12345,
    "equipos": None,
    "intervalo": 2.0,
    "jitter": 0.05,
    "duracion": 0.0,
    "ramp": 2.0,
    "seed": None,
    "formato": "equipo",
    "paso": 0.01,
    "escenario": ["normal"],
    "pct_alarma": 30.0,
    "pct_desconexion": 30.0,
    "desconexion_desde": 30.0,
    "rangos": {
        "CO2": [0.03, 0.8],
        "CO": [0.0, 15.0],
        "H2S": [0.0, 0.8],
        "NO2": [0.0, 0.1],
        "O2": [20.0, 21.5],
    },
    "verbose": False,
}


def cargar_config():
    cfg = json.loads(json.dumps(DEFAULTS))
    if os.path.isfile(CONFIG_SIM):
        with open(CONFIG_SIM, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        for clave, valor in data.items():
            if clave == "rangos" and isinstance(valor, dict):
                cfg["rangos"].update(valor)
            else:
                cfg[clave] = valor
    return cfg


def leer_conf_broker():
    try:
        with open(CONF_BROKER, "r", encoding="utf-8-sig") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def parse_args():
    p = argparse.ArgumentParser(
        description="Simulador de equipos para el Broker SDIMP (TCP).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--host", help="IP del broker")
    p.add_argument("--puerto", type=int, help="puerto TCP del broker")
    p.add_argument("--equipos", type=int, help="numero de equipos a simular")
    p.add_argument("--intervalo", type=float, help="segundos entre envios por equipo")
    p.add_argument("--jitter", type=float, help="segundos aleatorios extra entre envios")
    p.add_argument("--duracion", type=float, help="segundos de ejecucion (0 = indefinido)")
    p.add_argument("--ramp", type=float, help="segundos para escalonar el arranque de los equipos")
    p.add_argument("--seed", type=int, help="semilla aleatoria (reproducibilidad)")
    p.add_argument("--formato", choices=["equipo", "fijo"], help="formato de la trama enviada")
    p.add_argument("--paso", type=float, help="amplitud del random walk por trama (0 = valores fijos)")
    p.add_argument("--escenario", action="append", help="normal, alarma, desconexion (se combinan con comas)")
    p.add_argument("--pct-alarma", type=float, help="porcentaje de equipos en alarma")
    p.add_argument("--pct-desconexion", type=float, help="porcentaje de equipos que se desconectan")
    p.add_argument("--desconexion-desde", type=float, help="segundos tras los cuales se desconectan")
    p.add_argument("--rango", nargs="+", help="rangos por gas, p.ej. CO2=0.03,0.8 CO=0,15")
    p.add_argument("--verbose", action="store_true", default=None, help="log detallado por trama")
    return p.parse_args()


def aplicar_args(cfg, args):
    claves = (
        "host", "puerto", "equipos", "intervalo", "jitter", "duracion", "ramp",
        "seed", "formato", "paso", "pct_alarma", "pct_desconexion",
        "desconexion_desde",
    )
    for clave in claves:
        valor = getattr(args, clave)
        if valor is not None:
            cfg[clave] = valor
    if args.escenario:
        escenarios = []
        for item in args.escenario:
            escenarios += [x.strip().lower() for x in item.split(",") if x.strip()]
        cfg["escenario"] = escenarios
    if args.rango:
        for token in args.rango:
            if "=" not in token:
                raise SystemExit(f"--rango invalido: {token} (use GAS=min,max)")
            gas, rango = token.split("=", 1)
            gas = gas.strip().upper()
            try:
                minimo, maximo = (float(x) for x in rango.split(","))
            except ValueError:
                raise SystemExit(f"--rango invalido: {token} (use GAS=min,max)")
            cfg["rangos"][gas] = [minimo, maximo]
    if args.verbose is not None:
        cfg["verbose"] = args.verbose


def validar(cfg, conf_broker):
    if cfg["equipos"] is None:
        cfg["equipos"] = int(conf_broker.get("Equipos") or 15)
    if cfg["equipos"] < 1:
        raise SystemExit("--equipos debe ser >= 1")
    for escenario in cfg["escenario"]:
        if escenario not in ("normal", "alarma", "desconexion"):
            raise SystemExit(f"escenario invalido: {escenario}")
    if cfg["formato"] not in ("equipo", "fijo"):
        raise SystemExit(f"formato invalido: {cfg['formato']}")
    if cfg["intervalo"] < 0:
        raise SystemExit("--intervalo debe ser >= 0")
    if cfg["paso"] < 0:
        raise SystemExit("--paso debe ser >= 0")
    for gas in GASES:
        if gas not in cfg["rangos"]:
            raise SystemExit(f"falta el rango del gas {gas}")
        minimo, maximo = cfg["rangos"][gas]
        if minimo > maximo:
            raise SystemExit(f"rango invalido para {gas}: {minimo} > {maximo}")


def imprimir_cabecera(cfg, conf_broker):
    print("=" * 62)
    print(" Simulador de equipos - Broker SDIMP")
    print("-" * 62)
    print(f" Broker      : {cfg['host']}:{cfg['puerto']}")
    print(f" Equipos     : {cfg['equipos']} (ids 1..{cfg['equipos']})")
    print(f" Escenario   : {', '.join(cfg['escenario'])}")
    duracion = "indefinida" if cfg["duracion"] <= 0 else f"{cfg['duracion']} s"
    print(f" Duracion    : {duracion}")
    print(f" Intervalo   : {cfg['intervalo']} s (+ jitter {cfg['jitter']} s)")
    print(f" Ramp        : {cfg['ramp']} s")
    print(f" Formato     : {cfg['formato']}")
    print(f" Paso        : {cfg['paso']}")
    if cfg["seed"] is not None:
        print(f" Semilla     : {cfg['seed']}")
    if cfg["intervalo"] > 0:
        oferta = cfg["equipos"] / cfg["intervalo"]
        print(f" Oferta      : {oferta:.2f} tramas/s (techo teorico broker: ~5/s)")
        if oferta > 5.0:
            perdida = (oferta - 5.0) / oferta * 100.0
            print(f" Aviso       : oferta > 5/s; perdida teorica minima ~{perdida:.0f}%")
    else:
        print(" Oferta      : sin espera entre tramas (maxima velocidad)")
    for gas in GASES:
        minimo, maximo = cfg["rangos"][gas]
        print(f" Rango {gas:<4} : {minimo} - {maximo}")
    num_eq = conf_broker.get("Equipos")
    if num_eq and int(num_eq) < cfg["equipos"]:
        print("-" * 62)
        print(f" AVISO: data/conf.txt declara Equipos={num_eq}; el broker ignorara ids > {num_eq}.")
    elif num_eq and int(num_eq) > cfg["equipos"]:
        print("-" * 62)
        print(f" Pista: data/conf.txt declara Equipos={num_eq}; usa --equipos {num_eq} para simular todos.")
    if conf_broker.get("Direccion"):
        print(f" Mina broker : {conf_broker.get('Direccion')} -> {conf_broker.get('Servicio', '')}")
    print("-" * 62)
    print(" Ctrl+C para detener.")
    print("=" * 62)


def entero(campo):
    try:
        return int(float(campo))
    except ValueError:
        return None


class Simulador:
    def __init__(self, cfg):
        self.cfg = cfg
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.enviadas = {}
        self.acks = 0
        self.inicio = None

    def transcurrido(self):
        if self.inicio is None:
            return 0.0
        return time.monotonic() - self.inicio

    def registrar(self, eid):
        with self.lock:
            self.enviadas[eid] = self.enviadas.get(eid, 0) + 1

    def registrar_ack(self, cantidad):
        if cantidad <= 0:
            return
        with self.lock:
            self.acks += cantidad

    def log(self, mensaje):
        print(f"[{time.strftime('%H:%M:%S')}] {mensaje}", flush=True)

    def log_trama(self, eid, trama):
        if not self.cfg["verbose"]:
            return
        campos = trama.strip().split(" ")
        gases = " ".join(f"{GASES[i]}={campos[1 + i]}" for i in range(5))
        fechas = [entero(campo) for campo in campos[6:12]]
        if all(valor is not None for valor in fechas):
            anio, mes, dia, hora, minuto, segundo = fechas
            fecha = f"{anio}-{mes:02d}-{dia:02d}"
            hora_texto = f"{hora:02d}:{minuto:02d}:{segundo:02d}"
        else:
            fecha = "-".join(campos[6:9])
            hora_texto = ":".join(campos[9:12])
        self.log(f"EQ {eid:02d} {gases} | {fecha} {hora_texto} | trama: {trama.strip()}")

    def ejecutar(self):
        cfg = self.cfg
        self.inicio = time.monotonic()
        rnd = random.Random(cfg["seed"])
        ids = list(range(1, cfg["equipos"] + 1))
        total = len(ids)
        escenarios = set(cfg["escenario"])
        alarmas, desconectados = set(), set()
        if "alarma" in escenarios and cfg["pct_alarma"] > 0:
            cantidad = max(1, int(round(total * cfg["pct_alarma"] / 100.0)))
            alarmas = set(rnd.sample(ids, min(cantidad, total)))
        if "desconexion" in escenarios and cfg["pct_desconexion"] > 0:
            cantidad = max(1, int(round(total * cfg["pct_desconexion"] / 100.0)))
            desconectados = set(rnd.sample(ids, min(cantidad, total)))
        if alarmas:
            self.log(f"Equipos en alarma: {sorted(alarmas)}")
        if desconectados:
            self.log(f"Equipos que se desconectaran a los {cfg['desconexion_desde']} s: {sorted(desconectados)}")
        hilos = []
        for indice, eid in enumerate(ids):
            arranque = cfg["ramp"] * (indice / total) if total > 0 else 0.0
            hilo = Equipo(self, eid, eid in alarmas, eid in desconectados, arranque)
            hilo.daemon = True
            hilo.start()
            hilos.append(hilo)
        self.monitorear()
        self.stop.set()
        for hilo in hilos:
            hilo.join(timeout=2.0)
        self.resumen_final()

    def monitorear(self):
        cfg = self.cfg
        ultimo_resumen = 0.0
        while not self.stop.is_set():
            if cfg["duracion"] > 0 and self.transcurrido() >= cfg["duracion"]:
                self.log(f"Duracion alcanzada ({cfg['duracion']} s). Deteniendo...")
                break
            if self.transcurrido() - ultimo_resumen >= 5.0:
                ultimo_resumen = self.transcurrido()
                self.resumen_parcial()
            time.sleep(0.2)

    def resumen_parcial(self):
        with self.lock:
            total = sum(self.enviadas.values())
            acks = self.acks
            activos = len(self.enviadas)
        transcurrido = self.transcurrido()
        tasa = total / transcurrido if transcurrido > 0 else 0.0
        pendientes = max(0, total - acks)
        self.log(
            f"Resumen: {total} enviadas | {acks} ACKs | {pendientes} sin ACK | "
            f"{tasa:.2f} envios/s | equipos activos: {activos}/{self.cfg['equipos']} | {transcurrido:.0f} s"
        )

    def resumen_final(self):
        with self.lock:
            total = sum(self.enviadas.values())
            acks = self.acks
            detalle = dict(self.enviadas)
        transcurrido = self.transcurrido()
        tasa = total / transcurrido if transcurrido > 0 else 0.0
        perdida = max(0.0, (1.0 - acks / total) * 100.0) if total else 0.0
        print("-" * 62)
        print(f" Total: {total} tramas en {transcurrido:.1f} s ({tasa:.2f} tramas/s)")
        print(f" ACKs observados: {acks} | perdida estimada: {perdida:.1f}%")
        print(" ACKs = lecturas atendidas por el broker; pueden quedar ACK en vuelo al detener.")
        if detalle:
            conteos = ", ".join(f"EQ {eid:02d}={detalle[eid]}" for eid in sorted(detalle))
            print(f" Por equipo: {conteos}")
        sin_datos = [eid for eid in range(1, self.cfg["equipos"] + 1) if eid not in detalle]
        if sin_datos:
            print(f" Sin tramas: {sin_datos}")
        print("-" * 62)


class Equipo(threading.Thread):
    def __init__(self, sim, eid, es_alarma, es_desconectado, arranque):
        super().__init__(name=f"EQ{eid:02d}")
        self.sim = sim
        self.eid = eid
        self.es_alarma = es_alarma
        self.es_desconectado = es_desconectado
        self.arranque = arranque
        semilla = sim.cfg["seed"]
        if semilla is None:
            self.rnd = random.Random()
        else:
            self.rnd = random.Random(semilla * 1000003 + eid)
        self.sock = None
        self.valores = None
        self.o2_alarma_alta = self.rnd.random() < 0.5

    def desconectado_ahora(self):
        return self.es_desconectado and self.sim.transcurrido() >= self.sim.cfg["desconexion_desde"]

    def run(self):
        self.sim.stop.wait(self.arranque)
        while not self.sim.stop.is_set():
            if self.desconectado_ahora():
                self.cerrar()
                self.sim.log(f"EQ {self.eid:02d} desconectado (simulado)")
                return
            if not self.conectar():
                self.sim.stop.wait(2.0)
                continue
            try:
                self.bucle()
            except OSError:
                pass
            finally:
                self.sim.registrar_ack(self.drenar())
                self.cerrar()
            if self.sim.cfg["duracion"] > 0 and self.sim.transcurrido() >= self.sim.cfg["duracion"]:
                return

    def conectar(self):
        try:
            sock = socket.create_connection(
                (self.sim.cfg["host"], self.sim.cfg["puerto"]), timeout=5.0
            )
            sock.settimeout(None)
            self.sock = sock
            return True
        except OSError:
            return False

    def bucle(self):
        cfg = self.sim.cfg
        while not self.sim.stop.is_set() and not self.desconectado_ahora():
            if cfg["duracion"] > 0 and self.sim.transcurrido() >= cfg["duracion"]:
                return
            trama = self.construir_trama()
            try:
                self.sock.sendall(trama.encode("ascii"))
            except OSError:
                return
            self.sim.registrar(self.eid)
            self.sim.log_trama(self.eid, trama)
            self.sim.registrar_ack(self.drenar())
            espera = cfg["intervalo"]
            if cfg["jitter"] > 0:
                espera += self.rnd.uniform(0.0, cfg["jitter"])
            if espera > 0:
                self.esperar(espera)

    def esperar(self, espera):
        fin = time.monotonic() + espera
        while not self.sim.stop.is_set():
            restante = fin - time.monotonic()
            if restante <= 0:
                break
            self.sim.stop.wait(min(0.2, restante))
            self.sim.registrar_ack(self.drenar())

    def drenar(self):
        if self.sock is None:
            return 0
        total = 0
        try:
            self.sock.setblocking(False)
            while True:
                try:
                    datos = self.sock.recv(4096)
                except (BlockingIOError, InterruptedError):
                    break
                if not datos:
                    break
                total += len(datos)
        except OSError:
            pass
        finally:
            try:
                self.sock.setblocking(True)
            except OSError:
                pass
        return total

    def cerrar(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def zona(self, gas):
        if not self.es_alarma:
            return self.sim.cfg["rangos"][gas]
        if gas == "O2":
            return O2_ALARMA_ALTA if self.o2_alarma_alta else O2_ALARMA_BAJA
        return ZONA_ALARMA[gas]

    def inicializar_valores(self):
        self.valores = {gas: self.rnd.uniform(*self.zona(gas)) for gas in GASES}

    def generar_valores(self):
        if self.valores is None:
            self.inicializar_valores()
        paso = self.sim.cfg["paso"]
        if paso > 0:
            for gas in GASES:
                minimo, maximo = self.zona(gas)
                amplitud = maximo - minimo
                if amplitud <= 0:
                    continue
                delta = self.rnd.uniform(-paso, paso) * amplitud
                self.valores[gas] = min(max(self.valores[gas] + delta, minimo), maximo)
        return self.valores

    def formatear_sensor(self, gas, valor):
        if self.sim.cfg["formato"] == "equipo":
            return repr(float(round(valor, DECIMALES[gas])))
        return f"{valor:.{DECIMALES[gas]}f}"

    def formatear_fecha(self, ahora):
        if self.sim.cfg["formato"] == "equipo":
            campos = (ahora.tm_year, ahora.tm_mon, ahora.tm_mday, ahora.tm_hour, ahora.tm_min, ahora.tm_sec)
            return [repr(float(campo)) for campo in campos]
        return [
            f"{ahora.tm_year}",
            f"{ahora.tm_mon:02d}",
            f"{ahora.tm_mday:02d}",
            f"{ahora.tm_hour:02d}",
            f"{ahora.tm_min:02d}",
            f"{ahora.tm_sec:02d}",
        ]

    def construir_trama(self):
        valores = self.generar_valores()
        ahora = time.localtime()
        partes = [str(self.eid)]
        for gas in GASES:
            partes.append(self.formatear_sensor(gas, valores[gas]))
        partes += self.formatear_fecha(ahora)
        return " ".join(partes) + "\n"


def main():
    cfg = cargar_config()
    conf_broker = leer_conf_broker()
    args = parse_args()
    aplicar_args(cfg, args)
    validar(cfg, conf_broker)
    sim = Simulador(cfg)

    def al_detener(signum, frame):
        print()
        sim.log("Ctrl+C: deteniendo...")
        sim.stop.set()

    try:
        signal.signal(signal.SIGINT, al_detener)
    except ValueError:
        pass

    imprimir_cabecera(cfg, conf_broker)
    sim.ejecutar()


if __name__ == "__main__":
    main()

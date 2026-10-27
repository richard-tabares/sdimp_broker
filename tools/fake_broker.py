#!/usr/bin/env python3
"""Broker falso para probar el simulador sin abrir Processing.

Emula el comportamiento del broker real:
  - Acepta multiples clientes TCP.
  - Atiende 1 cliente por frame (5 fps), en round-robin entre los que tienen datos.
  - Escribe el byte ACK '1' y luego drena el buffer conservando solo la primera linea.

Uso:
    python3 fake_broker.py --duracion 30
    python3 fake_broker.py --puerto 12345 --duracion 0 --verbose
"""

import argparse
import select
import signal
import socket
import time

FRAME = 0.2


def parse_args():
    p = argparse.ArgumentParser(
        description="Broker falso (TCP) que emula al broker SDIMP para pruebas.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--host", default="127.0.0.1", help="IP de escucha")
    p.add_argument("--puerto", type=int, default=12345, help="puerto TCP de escucha")
    p.add_argument("--duracion", type=float, default=0.0, help="segundos de ejecucion (0 = indefinido)")
    p.add_argument("--verbose", action="store_true", default=False, help="imprime cada trama recibida")
    return p.parse_args()


def main():
    args = parse_args()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.puerto))
    srv.listen(300)
    srv.setblocking(False)

    print("=" * 62)
    print(" Broker falso - SDIMP")
    print("-" * 62)
    print(f" Escuchando : {args.host}:{args.puerto}")
    dur = "indefinida" if args.duracion <= 0 else f"{args.duracion} s"
    print(f" Duracion   : {dur}")
    print(f" Frame      : {FRAME} s (5 fps, 1 cliente por frame)")
    print("=" * 62)

    clientes = []
    buffers = {}
    ultimo = -1
    procesadas = 0
    descartadas = 0
    detener = {"flag": False}
    inicio = time.monotonic()

    def al_detener(signum, frame):
        print()
        detener["flag"] = True

    signal.signal(signal.SIGINT, al_detener)

    def resumen():
        transcurrido = time.monotonic() - inicio
        tasa = procesadas / transcurrido if transcurrido > 0 else 0.0
        print("-" * 62)
        print(f" PROCESADAS={procesadas} DESCARTADAS={descartadas} | {tasa:.2f} tramas/s | {transcurrido:.1f} s")
        print("-" * 62)

    while not detener["flag"]:
        if args.duracion > 0 and time.monotonic() - inicio >= args.duracion:
            break
        try:
            while True:
                cliente, _ = srv.accept()
                cliente.setblocking(False)
                clientes.append(cliente)
                buffers[cliente] = bytearray()
        except BlockingIOError:
            pass

        if clientes:
            listos, _, _ = select.select(clientes, [], [], 0)
            for cliente in listos:
                try:
                    datos = cliente.recv(65536)
                except OSError:
                    datos = b""
                if datos:
                    buffers[cliente] += datos
                else:
                    if cliente in clientes:
                        clientes.remove(cliente)
                    buffers.pop(cliente, None)

        total = len(clientes)
        for salto in range(total):
            indice = (ultimo + 1 + salto) % total
            cliente = clientes[indice]
            buffer = buffers.get(cliente, b"")
            if b"\n" in buffer:
                ultimo = indice
                try:
                    cliente.sendall(b"1")
                except OSError:
                    if cliente in clientes:
                        clientes.remove(cliente)
                    buffers.pop(cliente, None)
                    break
                lineas = [ln for ln in bytes(buffer).split(b"\n") if ln]
                buffers[cliente] = bytearray()
                procesadas += 1
                descartadas += max(0, len(lineas) - 1)
                if args.verbose:
                    print(f"RX {lineas[0].decode(errors='replace')}")
                break
        time.sleep(FRAME)

    resumen()
    srv.close()


if __name__ == "__main__":
    main()

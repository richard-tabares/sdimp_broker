void alarmaO2Compacta(float lecturaO, float valorBajaO, float valorAltaO, float xRectO, float yRectO, float wRectO, float hRectO) {
  if (lecturaO <= valorBajaO) {
    marcarAlarma(xRectO, yRectO, wRectO, hRectO, false);
    sonido1.trigger();
  }
  if (lecturaO >= valorAltaO) {
    marcarAlarma(xRectO, yRectO, wRectO, hRectO, true);
    sonido1.trigger();
  }
}

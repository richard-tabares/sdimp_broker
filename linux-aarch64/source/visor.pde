void myVisorCompacto(float valor, float minimo, float maximo, color c, float cx, float cy, float rExt, float rInt, float xTexto, float yTexto, int n1, int n2, String unidad) {
  //Gráficos circulares deshabilitados (código conservado para reactivarlos)
  //noFill();
  //strokeCap(SQUARE);
  //strokeWeight(rExt - rInt);
  //Arco de fondo
  //stroke(grisOscuro);
  //arc(cx, cy, rInt + rExt, rInt + rExt, PI, TWO_PI);
  //Arco de la lectura
  //float valorFin = map(constrain(valor, minimo, maximo), minimo, maximo, PI, TWO_PI);
  //stroke(c);
  //arc(cx, cy, rInt + rExt, rInt + rExt, PI, valorFin);
  //Valor numérico
  fill(c);
  textSize(min(rExt*0.95, alto*0.025));
  textAlign(LEFT, CENTER);
  text(nf(valor, n1, n2) + " " + unidad, xTexto, yTexto);
}

boolean stroke;
void applyStroke(boolean state) {
  stroke = state;
}

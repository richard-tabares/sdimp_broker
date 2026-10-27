void alarmaCompacta(float sensorLectura, float valorBaja, float xRect, float yRect, float wRect, float hRect) {
  if (sensorLectura >= valorBaja) {
    marcarAlarma(xRect, yRect, wRect, hRect, false);
    sonido1.trigger();
  }
}

void marcarAlarma(float x, float y, float w, float h, boolean alta) {
  stroke(rojo);
  strokeWeight(ancho/1920*3);
  noFill();
  rect(x, y, w, h, h*0.25);
  noStroke();
  fill(rojo);
  float t = min(w*0.06, h*0.45);
  float tx = x + w - t*1.6;
  float ty = y + h*0.5 - t*0.5;
  if (alta) {
    triangle(tx, ty + t, tx + t, ty + t, tx + t/2, ty); //up
  }
  else {
    triangle(tx, ty, tx + t, ty, tx + t/2, ty + t); //Down
  }
  noFill();
}

void myArc(int x, int y, int innerRadius, int outerRadius, float startingAngle, float endAngle, color from, color to) {
  float strokeOffset = endAngle - startingAngle;
  int maxLines = 360;
  strokeWeight(map(strokeOffset, 0, TWO_PI, 2, 5));
  strokeCap(SQUARE);

  for (float i = 0; i < maxLines; i ++) {
    pushMatrix();
    translate(x, y);
    rotate(map(i, 0, maxLines, startingAngle, endAngle));
    stroke(lerpColor(from, to, map(i, 0, maxLines, 0, 1)));
    
    line(innerRadius, 0, outerRadius, 0);
    popMatrix();
  }
  if (stroke) {
    strokeWeight(2);
    stroke(0);

    pushMatrix();
    translate(x, y);
    rotate(startingAngle);
    line(innerRadius, 0, outerRadius, 0);
    rotate(strokeOffset);
    line(innerRadius, 0, outerRadius, 0);
    popMatrix();

    noFill();
    strokeCap(PROJECT);
    arc(x, y, outerRadius*2, outerRadius*2, startingAngle, endAngle);
    arc(x, y, innerRadius*2, innerRadius*2, startingAngle, endAngle);
  }
}

//boolean stroke;
//void applyStroke(boolean state) {
//  stroke = state;
//}

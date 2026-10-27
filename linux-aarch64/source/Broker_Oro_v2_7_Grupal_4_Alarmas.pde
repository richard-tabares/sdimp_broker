import java.io.*;
import java.io.IOException;
import http.requests.*;
import de.bezier.data.sql.mapper.*;
import de.bezier.data.sql.*;
import processing.net.*;
import ddf.minim.*;

boolean prender=false;
Minim soundengine;
AudioSample sonido1;
PFont fuenteNormal;
PFont fuenteNegrita;
PImage logo;


String API_KEY = "SDIMP-ARIS-2026";



Server s;
JSONObject json;
String Direccion,Servicio,Empresa;
String input;
float data[];
String StrDia, StrMes;
String StrHora, StrMinutos, StrSegundos;
//----------
String[] DiaNombre = {"Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"};
String[] MesNombre = {"Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"};
int n =0;
int w;
XML xml;
Table table;
float ancho,alto;
int ancho1,alto1;

//Número de equipos (se lee de conf.txt, campo "Equipos")
int numEq = 15;

//Datos por equipo
float[][] sensor;       //[numEq][5]: 0=CO2, 1=CO, 2=H2S, 3=NO2, 4=O2
float[][] fecha;        //[numEq][6]: año, mes, día, hora, min, seg
boolean[] equipoConn;   //estado de conexión por equipo
int[] ultimaTrama;      //millis() de la última trama válida por equipo
int timeoutConexion;
int conectados=0;

EnviosHttp enviosHttp;
int maxTramasPorFrame = 10;
boolean logTramas = false;
int ultimoResumenHttp;

//Descriptores de cada columna de gas (orden visual: O2, NO2, H2S, CO, CO2)
String[] gasNombre = {"O2", "NO2", "H2S", "CO", "CO2"};
String[] gasUnidad = {"%", "ppm", "ppm", "ppm", "%"};
float[] gasMin = {0, 0, 0, 0, 0};
float[] gasMax = {30, 20, 50, 200, 5};
int[] gasSensor = {4, 3, 2, 1, 0}; //columna -> índice de sensor
int[] gasDec = {1, 2, 1, 1, 2};

//Umbrales de alarma por sensor (0=CO2, 1=CO, 2=H2S, 3=NO2, 4=O2)
float[] alarmaBaja = {1, 25, 1, 0.2, 19.5};
float[] alarmaAlta = {3, 75, 5, 5, 23.5};

//Colores
color rojo = color (255,0,0); // color círculo desconexión
color verde = color (0,255,0); // color círculo conexión
color gris = color (100,100,100); // color letra feche y hora
color grisOscuro = color(160,160,160); //fondo arco sensores
color negro = color(0, 0, 0); // color letra CO2
color azulC = color(0, 143, 254); // color letra O2
color azulO = color(0, 0, 255); // color letra NO2
color verdeC = color(0, 153, 51); // color letra CO
color naranja = color(255, 102, 0); // color letra H2S
color azulFondo = color(46, 75, 115); //fondo del tablero
color claroFondo = color(236, 236, 236); //cabecera
color franjaFondo = color(232, 232, 232); //fondo de cada fila
color franjaEstado = color(148, 170, 202); //sección de estado de cada fila

color[] gasColor = {azulC, azulO, naranja, verdeC, negro};

//Layout (se calcula en setup)
float yCabecera, yGases, yInicio, yFin, alturaFila;
float wEstado, xGauges, wGas;
float tamTituloEstacion;
float diametroEstado;
float padEstado, xTituloEstado, anchoTituloEstado;
float altoPie, margenPie, hLogo, wLogo, xLogo, yLogo;

int i=0;
int j=0;
int k=0;


/********************************************************************/
void settings() {
  fullScreen();
}

void setup() {
  ancho = width;
  alto = height;
  println("Canvas: " + width + "x" + height + " | display: " + displayWidth + "x" + displayHeight + " | density: " + displayDensity());
  json=loadJSONObject("conf.txt");
  Servicio = json.getString("Servicio");
  Direccion= json.getString("Direccion");
  Empresa = json.getString("Empresa");
  numEq = json.getInt("Equipos", 5);
  if(numEq < 1){
    numEq = 1;
  }
  timeoutConexion = json.getInt("TimeoutConexion", 10000);
  if(timeoutConexion < 1000){
    timeoutConexion = 1000;
  }

  maxTramasPorFrame = max(1, json.getInt("MaxTramasPorFrame", 10));
  logTramas = json.getBoolean("LogTramas", false);
  int httpWorkers = max(1, json.getInt("HttpWorkers", 4));
  int httpQueue = max(httpWorkers, json.getInt("HttpQueue", 50000));
  int httpTimeoutConexion = max(1000, json.getInt("HttpTimeoutConexion", 5000));
  int httpTimeoutLectura = max(1000, json.getInt("HttpTimeoutLectura", 10000));

  sensor = new float[numEq][5];
  fecha = new float[numEq][6];
  equipoConn = new boolean[numEq];
  ultimaTrama = new int[numEq];
  for(int eq=0; eq<numEq; eq++){
    ultimaTrama[eq] = millis() - timeoutConexion - 1;
  }

  fuenteNormal = createFont("SansSerif", 12);
  fuenteNegrita = createFont("SansSerif", 12, true);
  logo = loadImage("logo.png");

  calcularLayout();
  textFont(fuenteNormal);

  s = new Server(this, 12345);
  enviosHttp = new EnviosHttp(Servicio, Direccion, API_KEY, httpWorkers, httpQueue, httpTimeoutConexion, httpTimeoutLectura);
  ultimoResumenHttp = millis();
  soundengine = new Minim(this);
  sonido1 = soundengine.loadSample("02.mp3", 1024);
  frameRate(5);
}

void calcularLayout(){
  yCabecera = alto*0.075;
  yGases = alto*0.105;
  yInicio = alto*0.135;
  altoPie = alto*0.065;
  margenPie = alto*0.04;
  yFin = alto - altoPie - margenPie;
  alturaFila = (yFin - yInicio)/max(numEq, 5);

  padEstado = ancho*0.012;
  wEstado = ancho*0.14;
  diametroEstado = min(alturaFila*0.48, wEstado*0.20);
  xTituloEstado = padEstado + diametroEstado + padEstado;
  anchoTituloEstado = wEstado - xTituloEstado - padEstado;

  hLogo = altoPie*0.58;
  wLogo = hLogo * (logo != null ? logo.width/(float)logo.height : 0);
  xLogo = ancho - ancho*0.012 - wLogo;
  yLogo = yFin + (altoPie - hLogo)*0.5;

  tamTituloEstacion = min(alturaFila*0.38, alto*0.025);
  textFont(fuenteNegrita);
  textSize(tamTituloEstacion);
  float wTituloMax = textWidth("Estación " + nf(numEq, 2, 0));
  if(anchoTituloEstado > 0 && wTituloMax > anchoTituloEstado){
    tamTituloEstacion = tamTituloEstacion * (anchoTituloEstado / wTituloMax);
  }

  xGauges = wEstado + ancho*0.01;
  wGas = (ancho - xGauges - ancho*0.01)/5.0;
}

void draw() {
  if(ancho != width || alto != height){
    ancho = width;
    alto = height;
    calcularLayout();
    textFont(fuenteNormal);
  }

  recibirDatos();
  detectarConexion();
  dibujarTablero();

  if(millis() - ultimoResumenHttp >= 30000){
    enviosHttp.resumen();
    ultimoResumenHttp = millis();
  }
}

void dibujarTablero(){
  background(azulFondo);

  //Cabecera
  noStroke();
  fill(claroFondo);
  rect(0, 0, ancho, yInicio);

  fill(azulFondo);
  textSize(alto*0.032);
  textAlign(LEFT, CENTER);
  text("Broker", ancho*0.012, yCabecera*0.5);

  textSize(alto*0.026);
  textAlign(CENTER, CENTER);
  text(Empresa, ancho*0.5, yCabecera*0.5);

  textAlign(RIGHT, CENTER);
  text(day() + "/" + month() + "/" + year() + "   " + hour() + ":" + minute() + ":" + second(), ancho*0.988, yCabecera*0.5);

  //Encabezado de gases (nombre, unidad y rango se muestran una sola vez)
  textFont(fuenteNegrita);
  textSize(alto*0.024);
  textAlign(CENTER, CENTER);
  for(int col=0; col<5; col++){
    float cx = xGauges + col*wGas + wGas/2.0;
    fill(gasColor[col]);
    text(gasNombre[col] + " (" + gasUnidad[col] + ")  " + nf(gasMin[col],1,0) + " - " + nf(gasMax[col],1,0), cx, yGases);
  }
  textFont(fuenteNormal);

  //Borde inferior de la fila de encabezados
  noStroke();
  fill(franjaFondo);
  rect(0, yInicio, ancho, 1);
  fill(franjaEstado);
  rect(0, yInicio, wEstado, 1);

  //Filas de equipos
  for(int eq=0; eq<numEq; eq++){
    dibujarFila(eq);
  }

  //Pie
  noStroke();
  fill(255);
  rect(0, yFin, ancho, alto - yFin);
  fill(franjaEstado);
  rect(0, yFin, ancho, 1);

  textFont(fuenteNegrita);
  fill(azulFondo);
  textSize(min(altoPie*0.32, alto*0.018));
  textAlign(CENTER, CENTER);
  text("www.sdimp.com", ancho*0.5, yFin + altoPie*0.5);

  if(logo != null){
    imageMode(CORNER);
    image(logo, xLogo, yLogo, wLogo, hLogo);
  }
  textFont(fuenteNormal);
}

void dibujarFila(int eq){
  float yf = yInicio + eq*alturaFila;

  //Franja de fondo
  noStroke();
  fill(franjaFondo);
  rect(0, yf+1, ancho, alturaFila-2);
  fill(franjaEstado);
  rect(0, yf+1, wEstado, alturaFila-2);

  //Círculo de conexión
  if(equipoConn[eq]){
    fill(verde);
  }
  else{
    fill(rojo);
  }
  ellipse(padEstado + diametroEstado*0.5, yf + alturaFila*0.5, diametroEstado, diametroEstado);

  //Nombre de la estación
  fill(azulFondo);
  textSize(tamTituloEstacion);
  textAlign(LEFT, CENTER);
  text("Estación " + nf(eq+1, 2, 0), xTituloEstado, yf + alturaFila*0.5);

  //Sensores
  for(int col=0; col<5; col++){
    int si = gasSensor[col];
    float v = sensor[eq][si];
    float celdaX = xGauges + col*wGas;
    float cy = yf + alturaFila*0.5;
    float rExt = alturaFila*0.40;
    float rInt = rExt*0.60;
    myVisorCompacto(v, gasMin[si], gasMax[si], gasColor[col], celdaX + wGas*0.16, cy, rExt, rInt, celdaX + wGas*0.30, cy, 1, gasDec[si], gasUnidad[si]);

    if(equipoConn[eq]){
      if(si == 4){
        alarmaO2Compacta(v, alarmaBaja[si], alarmaAlta[si], celdaX + 2, yf + 2, wGas - 4, alturaFila - 4);
      }
      else{
        alarmaCompacta(v, alarmaBaja[si], celdaX + 2, yf + 2, wGas - 4, alturaFila - 4);
      }
    }
  }
}

//***************Recibir los datos y enviarlos al servicio*********************************
void recibirDatos(){
  for(int recibidas=0; recibidas<maxTramasPorFrame; recibidas++){
    Client cliente = s.available();
    if(cliente == null){
      break;
    }
    procesarTrama(cliente);
  }
}

void procesarTrama(Client cliente){
  try {
    cliente.write('1');
    input = cliente.readString();
    input = input.substring(0, input.indexOf("\n"));
    data = float(split(input, ' '));

    if(data.length < 12){
      enviosHttp.registrarInvalida();
      return;
    }

    int id = int(data[0]);
    if(id < 1 || id > numEq){
      enviosHttp.registrarInvalida();
      return;
    }

    int idx = id - 1;
    for(int t=0; t<5; t++){
      sensor[idx][t] = data[1+t];
    }
    for(int t=0; t<6; t++){
      fecha[idx][t] = data[6+t];
    }
    ultimaTrama[idx] = millis();

    String FechaNow = (nf(fecha[idx][0],0,0) + "-" + nf(fecha[idx][1],2,0) + "-" + nf(fecha[idx][2],2,0) + " " + nf(fecha[idx][3],2,0) + ":" + nf(fecha[idx][4],2,0) + ":" + nf(fecha[idx][5],0,0));
    enviosHttp.encolar(id, sensor[idx], FechaNow);

    if(logTramas){
      println("\t"+data[0]+"*"+ data[1]+"*"+ data[2]+"*"+ data[3]+"*"+ data[4]+"*"+ data[5]+"*"+nf(data[6],4,0)+"-"+ nf(data[7],2,0)+"-"+ nf(data[8],2,0)+" "+ nf(data[9],2,0)+":"+ nf(data[10],2,0)+":"+ nf(data[11],2,0));
    }
  }
  catch(Exception e){
    enviosHttp.registrarInvalida();
  }
}

void dispose(){
  if(enviosHttp != null){
    enviosHttp.detener();
  }
  super.dispose();
}

//Verifica conexión de equipos por tiempo desde su última trama válida
void detectarConexion(){
  conectados = 0;
  boolean cambio = false;
  int ahora = millis();
  for(int eq=0; eq<numEq; eq++){
    int transcurrido = ahora - ultimaTrama[eq];
    boolean visto = transcurrido >= 0 && transcurrido <= timeoutConexion;
    if(equipoConn[eq] && !visto){
      println("Equipo " + (eq+1) + " desconectado");
      cambio = true;
    }
    else if(!equipoConn[eq] && visto){
      println("Equipo " + (eq+1) + " conectado");
      cambio = true;
    }
    equipoConn[eq] = visto;
    if(visto){
      conectados = conectados + 1;
    }
  }
  if(cambio){
    println("Número de equipos conectados: " + conectados);
  }
}

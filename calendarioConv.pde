//import java.util.Date;
//void setup() {
//  FullDate.refresh();
 
//  println(FullDate.inf);
//  println(FullDate.y + "\t" + FullDate.mn);
public int dow(int d, int m, int y) {
  if (m < 3) {
    m += 12;
    y--;
  }
  return (d + int((m+1)*2.6) +  y + int(y/4) + 6*int(y/100) + int(y/400) + 6) % 7;
}

public void hora(){
    StrDia = str(day());
  StrMes = str(month());
  int Mes = month();
  if(day() < 10){StrDia = "0" + str(day()); }     
  if(month() < 10){StrMes = "0" + str(month());}  
  //Hora
  int hora = hour();
  int minuto = minute();
  int segundos = second();
  StrHora = str(hora);
  StrMinutos = str(minuto);
  StrSegundos = str(segundos);  
  if(hora<10){StrHora = "0" + str(hora);}
  if(minuto<10){StrMinutos = "0" + str(minuto);} 
  if(segundos<10){StrSegundos = "0" + str(segundos);}
  //text(FullDate.wn+", "+StrDia+" de "+FullDate.mn+" de "+year(),1091, 64);
  textSize(25);
  text( DiaNombre[w] + ", "+StrDia+" de " + MesNombre[Mes-1] + " de "+year(),866, 100);
  text(StrHora+":"+StrMinutos+":"+StrSegundos,952, 145);
}


boolean isConnected() {
  String[] file;
  try {    
    //file = loadStrings("http://textfiles.com/adventure/aencounter.txt");//el sitio debe ser HTTP no seguro!
    //Solo para verificar que hay conexión!
    //file = loadStrings("https://betagametest.com.co/sanei/sanei/testCon.txt");
    //xml = loadXML("https://www.eltiempo.com/rss/colombia.xml");
    xml = loadXML("https://www.sdimp.com/ValidaConexion.xml");
    //println(file[0]);
   // println(xml);
  } 
  catch (NullPointerException e) { 
    //println("Conexion no disponible...");
    return false;
  }
  return true;
}

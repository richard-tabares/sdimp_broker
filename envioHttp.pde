import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.NameValuePair;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.impl.client.DefaultHttpRequestRetryHandler;
import org.apache.http.message.BasicNameValuePair;
import org.apache.http.params.HttpConnectionParams;
import org.apache.http.util.EntityUtils;

class TramaEnvio {
  int id;
  String[] sensores = new String[5];
  String fecha;

  TramaEnvio(int id, float[] valores, String fecha) {
    this.id = id;
    this.fecha = fecha;
    for (int i = 0; i < 5; i++) {
      sensores[i] = Float.toString(valores[i]);
    }
  }
}

class EnviosHttp {
  String servicio;
  String mina;
  String apiKey;
  int workers;
  int capacidadPorCola;
  int capacidadTotal;
  int timeoutConexion;
  int timeoutLectura;

  ArrayList<ArrayBlockingQueue<TramaEnvio>> colas;
  ArrayList<TrabajadorHttp> trabajadores;

  AtomicLong recibidas = new AtomicLong();
  AtomicLong ok = new AtomicLong();
  AtomicLong errores = new AtomicLong();
  AtomicLong http404 = new AtomicLong();
  AtomicLong invalidas = new AtomicLong();
  AtomicLong descartadas = new AtomicLong();
  AtomicLong latenciaTotal = new AtomicLong();
  AtomicLong latenciaCuenta = new AtomicLong();
  AtomicBoolean errorImpreso = new AtomicBoolean(false);

  EnviosHttp(String servicio, String mina, String apiKey, int workers, int capacidadTotal, int timeoutConexion, int timeoutLectura) {
    this.servicio = servicio;
    this.mina = mina;
    this.apiKey = apiKey;
    this.workers = Math.max(1, workers);
    this.capacidadTotal = Math.max(this.workers, capacidadTotal);
    this.capacidadPorCola = Math.max(1, this.capacidadTotal / this.workers);
    this.capacidadTotal = this.capacidadPorCola * this.workers;
    this.timeoutConexion = timeoutConexion;
    this.timeoutLectura = timeoutLectura;

    colas = new ArrayList<ArrayBlockingQueue<TramaEnvio>>();
    trabajadores = new ArrayList<TrabajadorHttp>();

    for (int i = 0; i < this.workers; i++) {
      ArrayBlockingQueue<TramaEnvio> cola = new ArrayBlockingQueue<TramaEnvio>(this.capacidadPorCola);
      colas.add(cola);
      TrabajadorHttp trabajador = new TrabajadorHttp(i, cola, this);
      trabajador.setDaemon(true);
      trabajador.start();
      trabajadores.add(trabajador);
    }
  }

  void encolar(int id, float[] valores, String fecha) {
    recibidas.incrementAndGet();
    int indice = (id - 1) % workers;
    if (indice < 0) {
      indice = 0;
    }
    ArrayBlockingQueue<TramaEnvio> cola = colas.get(indice);
    TramaEnvio trama = new TramaEnvio(id, valores, fecha);
    if (!cola.offer(trama)) {
      TramaEnvio vieja = cola.poll();
      if (vieja != null) {
        descartadas.incrementAndGet();
      }
      if (!cola.offer(trama)) {
        descartadas.incrementAndGet();
      }
    }
  }

  void registrarInvalida() {
    invalidas.incrementAndGet();
  }

  void resumen() {
    long totalRecibidas = recibidas.get();
    long totalOk = ok.get();
    long totalErrores = errores.get();
    long total404 = http404.get();
    long totalInvalidas = invalidas.get();
    long totalDescartadas = descartadas.get();
    long totalLatencia = latenciaTotal.get();
    long cuentaLatencia = latenciaCuenta.get();
    long latenciaPromedio = cuentaLatencia > 0 ? totalLatencia / cuentaLatencia : 0;

    int colaActual = 0;
    int colaMaxima = 0;
    for (ArrayBlockingQueue<TramaEnvio> cola : colas) {
      int tamano = cola.size();
      colaActual += tamano;
      if (tamano > colaMaxima) {
        colaMaxima = tamano;
      }
    }

    println("HTTP recibidas=" + totalRecibidas + " ok=" + totalOk + " err=" + totalErrores + " 404=" + total404 + " invalidas=" + totalInvalidas + " cola=" + colaActual + "/" + capacidadTotal + " maxCola=" + colaMaxima + " descartadas=" + totalDescartadas + " latencia=" + latenciaPromedio + "ms");
  }

  void detener() {
    for (TrabajadorHttp trabajador : trabajadores) {
      trabajador.detener();
    }
    for (TrabajadorHttp trabajador : trabajadores) {
      try {
        trabajador.join(2000);
      }
      catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }
  }
}

class TrabajadorHttp extends Thread {
  int indice;
  BlockingQueue<TramaEnvio> cola;
  EnviosHttp envios;
  volatile boolean activo = true;
  DefaultHttpClient cliente;

  TrabajadorHttp(int indice, BlockingQueue<TramaEnvio> cola, EnviosHttp envios) {
    super("http-" + indice);
    this.indice = indice;
    this.cola = cola;
    this.envios = envios;
  }

  void detener() {
    activo = false;
    interrupt();
  }

  public void run() {
    cliente = new DefaultHttpClient();
    HttpConnectionParams.setConnectionTimeout(cliente.getParams(), envios.timeoutConexion);
    HttpConnectionParams.setSoTimeout(cliente.getParams(), envios.timeoutLectura);
    HttpConnectionParams.setStaleCheckingEnabled(cliente.getParams(), true);
    cliente.setHttpRequestRetryHandler(new DefaultHttpRequestRetryHandler(0, false));

    while (activo) {
      TramaEnvio trama = null;
      try {
        trama = cola.poll(250, TimeUnit.MILLISECONDS);
      }
      catch (InterruptedException e) {
        if (!activo) {
          break;
        }
        continue;
      }
      if (trama != null) {
        enviar(trama);
      }
    }

    cliente.getConnectionManager().shutdown();
  }

  void enviar(TramaEnvio trama) {
    long inicio = System.currentTimeMillis();
    HttpPost post = null;

    try {
      List<NameValuePair> parametros = new ArrayList<NameValuePair>();
      parametros.add(new BasicNameValuePair("apikey", envios.apiKey));
      parametros.add(new BasicNameValuePair("mina", envios.mina));
      for (int i = 0; i < 5; i++) {
        parametros.add(new BasicNameValuePair("S" + (i + 1), trama.sensores[i]));
      }
      parametros.add(new BasicNameValuePair("equipo", Integer.toString(trama.id)));
      parametros.add(new BasicNameValuePair("fecha", trama.fecha));

      post = new HttpPost(envios.servicio);
      post.setEntity(new UrlEncodedFormEntity(parametros, "ISO-8859-1"));
      HttpResponse respuesta = cliente.execute(post);
      int codigo = respuesta.getStatusLine().getStatusCode();
      HttpEntity entidad = respuesta.getEntity();
      String cuerpo = "";
      if (entidad != null) {
        if (codigo == 200) {
          EntityUtils.consume(entidad);
        }
        else {
          cuerpo = EntityUtils.toString(entidad);
        }
      }

      if (codigo == 200) {
        envios.ok.incrementAndGet();
      }
      else {
        if (codigo == 404) {
          envios.http404.incrementAndGet();
        }
        envios.errores.incrementAndGet();
        if (envios.errorImpreso.compareAndSet(false, true)) {
          println("HTTP error " + codigo + " en equipo " + trama.id + ": " + cuerpo);
        }
      }
    }
    catch (Exception e) {
      if (post != null) {
        post.abort();
      }
      envios.errores.incrementAndGet();
      if (envios.errorImpreso.compareAndSet(false, true)) {
        println("HTTP error de red: " + e.getClass().getSimpleName());
      }
    }
    finally {
      envios.latenciaTotal.addAndGet(System.currentTimeMillis() - inicio);
      envios.latenciaCuenta.incrementAndGet();
    }
  }
}

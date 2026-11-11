"""
Ventanas emergentes del sistema de emergencias (tkinter), en el mismo estilo
de mostrar_dialogo.py visto en clase. Elixir (Emergencias.Interfaz.Ventanas)
ejecuta este script y lee la respuesta por la salida estándar.

Uso:
    python dialogo.py info       TITULO ARCHIVO_TEXTO
    python dialogo.py error      TITULO ARCHIVO_TEXTO
    python dialogo.py formulario TITULO CAMPO1 CAMPO2 ...   (un "*" al inicio = campo oculto;
                                                             "Etiqueta|op1|op2" = lista desplegable)
    python dialogo.py menu       TITULO OPCION1 OPCION2 ...

Respuesta: formulario -> JSON con la lista de valores; menu -> número de la
opción (desde 0). Si el usuario cancela, no se imprime nada.
"""

import json
import os
import sys
import tkinter as tk
from tkinter import messagebox, scrolledtext, ttk

FUENTE = ("Segoe UI", 10)
RAYA = " – "  # "ES01 – perro"
PRUEBA = os.environ.get("EMERGENCIAS_PRUEBA") == "1"  # cierra sola la ventana (pruebas)


def ventana(titulo):
    raiz = tk.Tk()
    raiz.title(titulo)
    raiz.attributes("-topmost", True)
    raiz.resizable(True, True)
    if PRUEBA:
        raiz.after(800, raiz.destroy)
    return raiz


def leer(ruta):
    with open(ruta, encoding="utf-8") as archivo:
        return archivo.read()


def info(titulo, ruta, es_error=False):
    texto = leer(ruta)
    if len(texto) < 300 and texto.count("\n") < 6:
        raiz = tk.Tk()
        raiz.withdraw()
        if PRUEBA:
            raiz.after(800, raiz.destroy)
            return
        (messagebox.showerror if es_error else messagebox.showinfo)(titulo, texto)
        return

    raiz = ventana(titulo)
    caja = scrolledtext.ScrolledText(raiz, width=110, height=28, font=("Consolas", 10), wrap="none")
    caja.insert("1.0", texto)
    caja.configure(state="disabled")
    caja.pack(fill="both", expand=True, padx=8, pady=8)
    tk.Button(raiz, text="Aceptar", width=14, command=raiz.destroy).pack(pady=(0, 8))
    raiz.mainloop()


def formulario(titulo, campos):
    raiz = ventana(titulo)
    entradas = []
    resultado = {"valores": None}

    for fila, campo in enumerate(campos):
        oculto = campo.startswith("*")
        etiqueta, *opciones = (campo[1:] if oculto else campo).split("|")
        tk.Label(raiz, text=etiqueta, font=FUENTE, anchor="w").grid(row=fila, column=0, sticky="w", padx=8, pady=4)
        if opciones:
            # Lista con los códigos
            entrada = ttk.Combobox(raiz, values=opciones, width=43, font=FUENTE)
        else:
            entrada = tk.Entry(raiz, width=45, font=FUENTE, show="*" if oculto else "")
        entrada.grid(row=fila, column=1, padx=8, pady=4)
        entradas.append(entrada)

    def aceptar(_evento=None):
        # Solo se envía el código
        resultado["valores"] = [e.get().split(RAYA)[0].strip() for e in entradas]
        raiz.destroy()

    botones = tk.Frame(raiz)
    botones.grid(row=len(campos), column=0, columnspan=2, pady=8)
    tk.Button(botones, text="Aceptar", width=12, command=aceptar).pack(side="left", padx=6)
    tk.Button(botones, text="Cancelar", width=12, command=raiz.destroy).pack(side="left", padx=6)
    raiz.bind("<Return>", aceptar)
    if entradas:
        entradas[0].focus_set()
    raiz.mainloop()

    if resultado["valores"] is not None:
        print(json.dumps(resultado["valores"], ensure_ascii=False))


def menu(titulo, opciones):
    raiz = ventana(titulo)
    elegida = {"indice": None}

    def elegir(indice):
        elegida["indice"] = indice
        raiz.destroy()

    columnas = 3
    for indice, opcion in enumerate(opciones):
        boton = tk.Button(raiz, text=opcion, width=34, font=FUENTE, command=lambda i=indice: elegir(i))
        boton.grid(row=indice // columnas, column=indice % columnas, padx=6, pady=4)
    raiz.mainloop()

    if elegida["indice"] is not None:
        print(elegida["indice"])


def main():
    modo, titulo, *resto = sys.argv[1:]
    if modo == "info":
        info(titulo, resto[0])
    elif modo == "error":
        info(titulo, resto[0], es_error=True)
    elif modo == "formulario":
        formulario(titulo, resto)
    elif modo == "menu":
        menu(titulo, resto)


if __name__ == "__main__":
    main()

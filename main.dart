import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SAMIApp());
}

class SAMIApp extends StatelessWidget {
  const SAMIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'S.A.M.I',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ==========================================
// 1. SPLASH SCREEN
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade900,
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.precision_manufacturing, size: 100, color: Colors.white),
            SizedBox(height: 20),
            Text('S.A.M.I.', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. ACCESO Y REGISTRO
// ==========================================
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadStoredEmail();
  }

  _loadStoredEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailController.text = prefs.getString('saved_email') ?? "";
      _rememberMe = _emailController.text.isNotEmpty;
    });
  }

  _saveEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailController.text.trim());
    } else {
      await prefs.remove('saved_email');
    }
  }

  bool _isSecure(String p) => RegExp(r'^(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#$&*~]).{8,}$').hasMatch(p);
  bool _isValidEmail(String e) => RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(e);
  bool _isValidEmployeeNo(String n) => RegExp(r'^\d{8}$').hasMatch(n);

  void _notify(String m, {bool isError = true}) {
    messengerKey.currentState?.removeCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: isError ? Colors.red.shade900 : Colors.green.shade800,
    ));
  }

  Future<void> _login() async {
    try {
      UserCredential res = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passController.text.trim(),
      );
      if (!res.user!.emailVerified) {
        await _auth.signOut();
        _notify("Verifica tu correo antes de entrar.");
        return;
      }

      // 👉 NUEVA VALIDACIÓN: Verificar si la cuenta fue eliminada por un Admin
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(res.user!.uid).get();
      if (!userDoc.exists) {
        await _auth.signOut();
        _notify("Tu cuenta ha sido eliminada o desactivada por un administrador.");
        return;
      }

      await _saveEmail();
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (e) {
      _notify("Acceso denegado. Revisa tus datos.");
    }
  }

  void _showRegister() {
    final nameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final empCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Registro S.A.M.I.'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre(s)')),
              TextField(controller: lastNameCtrl, decoration: const InputDecoration(labelText: 'Apellido(s)')),
              TextField(
                controller: empCtrl,
                decoration: const InputDecoration(labelText: 'No. Empleado (8 dígitos)'),
                keyboardType: TextInputType.number,
              ),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Correo')),
              TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              String email = emailCtrl.text.trim();
              String empNo = empCtrl.text.trim();
              String pass = passCtrl.text.trim();

              if (!_isValidEmployeeNo(empNo)) { _notify("ID debe ser de 8 números."); return; }
              if (!_isValidEmail(email)) { _notify("Correo inválido."); return; }
              if (!_isSecure(pass)) { _notify("Contraseña débil."); return; }

              try {
                final duplicate = await _firestore.collection('users').where('employee_no', isEqualTo: empNo).get();
                if (duplicate.docs.isNotEmpty) { _notify("Este ID ya existe."); return; }

                UserCredential res = await _auth.createUserWithEmailAndPassword(email: email, password: pass);
                await res.user!.sendEmailVerification();

                await _firestore.collection('users').doc(res.user!.uid).set({
                  'name': nameCtrl.text.trim(),
                  'last_name': lastNameCtrl.text.trim(),
                  'employee_no': empNo,
                  'role': 'Usuario',
                  'created_at': FieldValue.serverTimestamp(),
                });

                if (context.mounted) Navigator.pop(context);
                await _auth.signOut();
                _notify("¡Cuenta creada! Verifica tu correo.", isError: false);
              } catch (e) { _notify("Error: $e"); }
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso S.A.M.I.')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Correo')),
            TextField(controller: _passController, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            CheckboxListTile(
              title: const Text("Recordar usuario"),
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v!),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _login, child: const Text('Iniciar Sesión')),
            TextButton(onPressed: _showRegister, child: const Text('Crear cuenta')),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. MENÚ PRINCIPAL
// ==========================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _rfidId;
  String _name = "Usuario";
  String _role = "Usuario";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  void _showOrderConfirmationDialog(String orderId, String materialId, String materialName, int stockActual) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('orders').doc(orderId).snapshots(),
          builder: (context, snapshot) {
            String titleText = "Confirmación de Pedido";
            Widget contentWidget = const SizedBox();
            bool mostrarBotonConfirmar = true;

            if (snapshot.hasData && snapshot.data!.exists) {
              var orderData = snapshot.data!.data() as Map<String, dynamic>;
              String status = orderData['status'] ?? 'Pendiente';

              switch (status) {
                case 'Pendiente':
                  mostrarBotonConfirmar = true;
                  contentWidget = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.help_outline, size: 60, color: Colors.blue),
                      const SizedBox(height: 15),
                      Text(
                        "¿Confirmas que deseas retirar el material:\n\n👉 $materialName?",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  );
                  break;

                case 'Confirmado':
                  mostrarBotonConfirmar = false;
                  titleText = "SAMI Respondiendo";
                  contentWidget = const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text("Estableciendo conexión con el hardware...", textAlign: TextAlign.center),
                    ],
                  );
                  break;

                case 'Validando RFID':
                  mostrarBotonConfirmar = false;
                  titleText = "🔒 Verificación Requerida";
                  contentWidget = const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.credit_card, size: 60, color: Colors.orange),
                      SizedBox(height: 20),
                      Text(
                        "Por favor, acerque su GAFETE FÍSICO al lector de S.A.M.I.\n\nVerificando identidad del empleado...",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                  break;

                case 'Despachando':
                  mostrarBotonConfirmar = false;
                  titleText = "⚙️ Despachando...";
                  contentWidget = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.green),
                      const SizedBox(height: 20),
                      Text(
                        "¡Gafete verificado!\n\nDejando caer pieza: $materialName\nEsperando sensor de proximidad...",
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                  break;

                case 'Completado':
                  Future.delayed(Duration.zero, () async {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                    await _db.collection('materials').doc(materialId).update({'stock': stockActual - 1});
                    messengerKey.currentState?.showSnackBar(const SnackBar(
                      content: Text("¡Pedido verificado y despachado con éxito!"),
                      backgroundColor: Colors.green,
                    ));
                  });
                  break;

                case 'Cancelado':
                case 'Rechazado':
                  Future.delayed(Duration.zero, () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                    String msgError = (status == "Cancelado")
                        ? "Pedido cancelado o Gafete incorrecto."
                        : "Error: S.A.M.I no detectó la caída del objeto.";
                    messengerKey.currentState?.showSnackBar(SnackBar(
                      content: Text(msgError),
                      backgroundColor: Colors.red,
                    ));
                  });
                  break;
              }
            }

            return AlertDialog(
              title: Text(titleText),
              content: contentWidget,
              actions: [
                TextButton(
                  onPressed: () async {
                    await _db.collection('orders').doc(orderId).update({'status': 'Cancelado'});
                  },
                  child: const Text("Cancelar", style: TextStyle(color: Colors.red)),
                ),
                if (mostrarBotonConfirmar)
                  ElevatedButton(
                    onPressed: () async {
                      await _db.collection('orders').doc(orderId).update({'status': 'Confirmado'});
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text("Sí, despachar"),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _fetchUserData() {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      _db.collection('users').doc(u.uid).snapshots().listen((d) async {
        if (d.exists && mounted) {
          setState(() {
            _name = d.data()?['name'] ?? "Usuario";
            _role = d.data()?['role'] ?? "Usuario";
            _rfidId = d.data()?['rfid_id'];
          });
        }
        // 👉 NUEVA VALIDACIÓN: Expulsar en tiempo real si el documento desaparece
        else if (!d.exists && mounted) {
          await FirebaseAuth.instance.signOut(); // Cierra su sesión

          messengerKey.currentState?.showSnackBar(const SnackBar(
            content: Text("Sesión cerrada. Tu cuenta ha sido eliminada del sistema."),
            backgroundColor: Colors.red,
          ));

          // Redirigir al Login y borrar el historial de pantallas para que no pueda regresar
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthPage()),
                (route) => false,
          );
        }
      });
    }
  }

  Future<void> _order(String n, String id, int s) async {
    if (_rfidId == null || _rfidId!.isEmpty) {
      _notify("Primero debes vincular tu tarjeta RFID en Ajustes de Perfil.");
      return;
    }
    if (s <= 0) {
      _notify("Sin stock disponible.");
      return;
    }

    try {
      DocumentReference orderRef = await _db.collection('orders').add({
        'material': n,
        'materialId': id,
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'userName': _name,
        'rfid_id': _rfidId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'Pendiente',
      });
      if (mounted) _showOrderConfirmationDialog(orderRef.id, id, n, s);
    } catch (e) {
      _notify("Error al procesar la solicitud de pedido.");
    }
  }

  void _notify(String m) {
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = _role == "Administrador";
    return DefaultTabController(
      key: ValueKey(_role),
      length: isAdmin ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('¡Hola, $_name!'),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
            ),
            IconButton(icon: const Icon(Icons.logout), onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
            }),
          ],
          bottom: TabBar(tabs: [
            const Tab(text: 'Inventario'),
            const Tab(text: 'Mis Pedidos'),
            if (isAdmin) const Tab(text: 'Ajustes'),
          ]),
        ),
        body: TabBarView(
          children: [
            _inventoryGrid(),
            _historyView(),
            if (isAdmin) _settingsView(),
          ],
        ),
      ),
    );
  }

  Widget _inventoryGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('materials').snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: s.data!.docs.length,
          itemBuilder: (c, i) {
            var d = s.data!.docs[i];
            var data = d.data() as Map<String, dynamic>;
            int stockActual = data['stock'] ?? 0;

            Color colorFondo;
            if (stockActual <= 0) {
              colorFondo = const Color(0xFFED736B);
            } else if (stockActual == 1) {
              colorFondo = const Color(0xFFF7BC4F);
            } else {
              colorFondo = const Color(0xFFB2F7C2);
            }

            return Card(
              color: colorFondo,
              elevation: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stock: $stockActual',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: stockActual > 0 ? () => _order(data['name'], d.id, stockActual) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(stockActual > 0 ? 'Pedir' : 'Agotado'),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _historyView() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Usuario no autenticado."));
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('orders').where('userId', isEqualTo: user.uid).orderBy('timestamp', descending: true).snapshots(),
      builder: (c, s) {
        if (s.hasError) return const Center(child: Text("Error: historial no disponible."));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.docs.isEmpty) return const Center(child: Text("Aún no tienes pedidos."));
        return ListView(
          children: s.data!.docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            Timestamp? ts = data['timestamp'] as Timestamp?;
            DateTime? t = ts?.toDate();
            String timeStr = t != null ? "${t.day}/${t.month} ${t.hour}:${t.minute}" : "Sincronizando...";
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(data['material'] ?? 'Material'),
              subtitle: Text('Estado: ${data['status']}'),
              trailing: Text(timeStr, style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _settingsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Panel de Administración", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.inventory, color: Colors.blue),
          title: const Text("Rellenar Stock"),
          subtitle: const Text("Ajustar cantidades de materiales"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showStockEditor(),
        ),
        ListTile(
          leading: const Icon(Icons.filter_alt, color: Colors.purple),
          title: const Text("Historial de Pedidos Global"),
          subtitle: const Text("Buscar por usuario, material, fecha y estado"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showGlobalOrders(),
        ),
        // 👉 NUEVO: ACCESO A GESTIÓN DE USUARIOS
        ListTile(
          leading: const Icon(Icons.bar_chart, color: Colors.orange), // Ícono de gráfico
          title: const Text("Estadísticas de Consumo"),
          subtitle: const Text("Material más pedido y métricas"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MaterialStatsScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.group_remove, color: Colors.red),
          title: const Text("Gestionar Usuarios"),
          subtitle: const Text("Eliminar cuentas y limpiar sus historiales"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showUserManagement(),
        ),
      ],
    );
  }

  void _showStockEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Gestión de Inventario", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db.collection('materials').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var doc = snapshot.data!.docs[index];
                      var data = doc.data() as Map;
                      return ListTile(
                        title: Text(data['name']),
                        subtitle: Text("Stock: ${data['stock']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => doc.reference.update({'stock': data['stock'] - 1})),
                            IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => doc.reference.update({'stock': data['stock'] + 1})),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGlobalOrders() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AdminOrdersSheet(db: _db),
    );
  }

  // 👉 NUEVA FUNCIÓN: DESPLEGAR PANEL DE ELIMINACIÓN DE USUARIOS
  void _showUserManagement() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AdminUsersSheet(db: _db),
    );
  }
}

// ==========================================
// 4. PANTALLA DE PERFIL
// ==========================================
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final user = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;
  final _rfidCtrl = TextEditingController();

  @override
  void dispose() {
    _rfidCtrl.dispose();
    super.dispose();
  }

  Future<void> _obtenerGafeteDeSami() async {
    try {
      DocumentSnapshot snap = await firestore.collection('sistema').doc('estado').get();
      if (snap.exists && snap.data() != null) {
        var data = snap.data() as Map<String, dynamic>;
        String lastRfid = data['ultimo_rfid_leido'] ?? '';

        if (lastRfid.isNotEmpty) {
          setState(() {
            _rfidCtrl.text = lastRfid;
          });
          messengerKey.currentState?.showSnackBar(const SnackBar(
            content: Text("¡Gafete obtenido de S.A.M.I con éxito!"),
            backgroundColor: Colors.green,
          ));
        } else {
          messengerKey.currentState?.showSnackBar(const SnackBar(
            content: Text("No hay gafetes recientes. Pasa tu tarjeta por la máquina primero."),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (e) {
      messengerKey.currentState?.showSnackBar(const SnackBar(
        content: Text("Error al comunicarse con la base de datos."),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ajustes de Perfil")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: firestore.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var data = snapshot.data!.data() as Map<String, dynamic>;
          final nameCtrl = TextEditingController(text: data['name'] ?? '');
          final lastCtrl = TextEditingController(text: data['last_name'] ?? '');

          if (_rfidCtrl.text.isEmpty && data['rfid_id'] != null) {
            _rfidCtrl.text = data['rfid_id'];
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
                const SizedBox(height: 30),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nombre(s)")),
                const SizedBox(height: 15),
                TextField(controller: lastCtrl, decoration: const InputDecoration(labelText: "Apellidos")),
                const SizedBox(height: 15),
                TextField(
                  enabled: false,
                  controller: TextEditingController(text: data['employee_no'] ?? 'N/A'),
                  decoration: const InputDecoration(
                      labelText: "No. Empleado (Inmodificable)",
                      filled: true,
                      suffixIcon: Icon(Icons.lock)
                  ),
                ),
                const SizedBox(height: 15),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Vinculación de Gafete / Tarjeta",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _rfidCtrl,
                                decoration: const InputDecoration(
                                  labelText: "ID único RFID",
                                  hintText: "Ej: A1B2C3D4",
                                  border: OutlineInputBorder(),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 60,
                              child: ElevatedButton(
                                onPressed: _obtenerGafeteDeSami,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                ),
                                child: const Icon(Icons.nfc, color: Colors.white, size: 30),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            "Tip: Pasa tu tarjeta por S.A.M.I. y presiona el botón naranja para copiar el código.",
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      String nuevoRfid = _rfidCtrl.text.trim().toUpperCase();
                      if (nuevoRfid.isNotEmpty) {
                        final query = await firestore
                            .collection('users')
                            .where('rfid_id', isEqualTo: nuevoRfid)
                            .get();
                        if (query.docs.isNotEmpty && query.docs.first.id != user!.uid) {
                          messengerKey.currentState?.showSnackBar(const SnackBar(
                            content: Text("Esta tarjeta ya está vinculada a otro empleado."),
                            backgroundColor: Colors.red,
                          ));
                          return;
                        }
                      }

                      await firestore.collection('users').doc(user!.uid).update({
                        'name': nameCtrl.text.trim(),
                        'last_name': lastCtrl.text.trim(),
                        'rfid_id': nuevoRfid.isEmpty ? null : nuevoRfid,
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        messengerKey.currentState?.showSnackBar(const SnackBar(
                          content: Text("Datos y Tarjeta RFID guardados correctamente."),
                          backgroundColor: Colors.green,
                        ));
                      }
                    },
                    child: const Text("Guardar Cambios"),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 5. PANEL GLOBAL DE PEDIDOS
// ==========================================
class AdminOrdersSheet extends StatefulWidget {
  final FirebaseFirestore db;
  const AdminOrdersSheet({super.key, required this.db});

  @override
  State<AdminOrdersSheet> createState() => _AdminOrdersSheetState();
}

class MaterialStatsScreen extends StatefulWidget {
  const MaterialStatsScreen({super.key});

  @override
  State<MaterialStatsScreen> createState() => _MaterialStatsScreenState();
}

class _MaterialStatsScreenState extends State<MaterialStatsScreen> {
  String _selectedPeriod = 'Este Mes';
  final List<String> _periods = ['Hoy', 'Esta Semana', 'Este Mes', 'Todo el tiempo'];

  DateTime _getStartDate() {
    DateTime now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Hoy': return DateTime(now.year, now.month, now.day);
      case 'Esta Semana': return now.subtract(Duration(days: now.weekday - 1));
      case 'Este Mes': return DateTime(now.year, now.month, 1);
      default: return DateTime(2024, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime startDate = _getStartDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis S.A.M.I.', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('status', isEqualTo: 'Completado') // Solo los que se entregaron
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          // Procesar datos
          Map<String, int> counts = {};
          for (var doc in snapshot.data!.docs) {
            String material = doc['material'] ?? 'N/A';
            counts[material] = (counts[material] ?? 0) + 1;
          }

          if (counts.isEmpty) {
            return _noDataView();
          }

          var sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          int total = counts.values.fold(0, (sum, item) => sum + item);
          var topMaterial = sorted.first;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _periodSelector(),
                const SizedBox(height: 20),

                // --- TARJETA DEL GANADOR ---
                _winnerCard(topMaterial.key, topMaterial.value, total),

                const SizedBox(height: 30),
                const Text("Gráfico de Demanda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                // --- GRÁFICO DE BARRAS PERSONALIZADO ---
                _customBarChart(sorted, total),

                const SizedBox(height: 30),
                const Text("Desglose Detallado", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),

                // --- LISTA DE MATERIALES ---
                ...sorted.map((e) => ListTile(
                  leading: const Icon(Icons.inventory_2, color: Colors.blueGrey),
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text("${e.value} piezas", style: const TextStyle(fontSize: 16)),
                )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _periodSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
      child: DropdownButton<String>(
        value: _selectedPeriod,
        isExpanded: true,
        underline: const SizedBox(),
        onChanged: (v) => setState(() => _selectedPeriod = v!),
        items: _periods.map((p) => DropdownMenuItem(value: p, child: Text("Periodo: $p"))).toList(),
      ),
    );
  }

  Widget _winnerCard(String name, int qty, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade600]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          const Icon(Icons.stars, color: Colors.amber, size: 40),
          const SizedBox(height: 10),
          const Text("EL MÁS PEDIDO", style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2)),
          Text(name.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text("$qty entregas exitosas", style: const TextStyle(color: Colors.white, fontSize: 18)),
          Text("${((qty / total) * 100).toStringAsFixed(1)}% del consumo total", style: const TextStyle(color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _customBarChart(List<MapEntry<String, int>> data, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: data.map((entry) {
          double widthFactor = entry.value / data.first.value; // Proporción relativa al máximo
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      flex: (widthFactor * 100).toInt(),
                      child: Container(
                        height: 25,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade800]),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - widthFactor) * 100).toInt() + 1,
                      child: const SizedBox(),
                    ),
                    const SizedBox(width: 10),
                    Text("${entry.value}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _noDataView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.query_stats, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          const Text("No hay datos para este periodo", style: TextStyle(color: Colors.grey, fontSize: 16)),
          _periodSelector(),
        ],
      ),
    );
  }
}2

class _AdminOrdersSheetState extends State<AdminOrdersSheet> {
  String _statusFilter = "Todos";
  String _materialFilter = "Todos";
  String _userFilter = "";
  DateTime? _dateFilter;
  List<String> _materialsList = ["Todos"];

  final List<String> _statuses = [
    "Todos",
    "Pendiente",
    "Confirmado",
    "Validando RFID",
    "Despachando",
    "Completado",
    "Cancelado",
    "Rechazado"
  ];

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  void _loadMaterials() async {
    var snap = await widget.db.collection('materials').get();
    if (mounted) {
      setState(() {
        _materialsList = ["Todos"] + snap.docs.map((d) => d['name'] as String).toList();
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completado': return Colors.green;
      case 'Cancelado':
      case 'Rechazado': return Colors.red;
      case 'Pendiente': return Colors.blue;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Control Global de Pedidos", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: "Buscar por nombre de usuario...",
                    prefixIcon: Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => setState(() => _userFilter = v.toLowerCase()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _materialFilter,
                        decoration: const InputDecoration(labelText: "Material", border: InputBorder.none),
                        items: _materialsList.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setState(() => _materialFilter = v!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: const InputDecoration(labelText: "Estado", border: InputBorder.none),
                        items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setState(() => _statusFilter = v!),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _dateFilter == null
                          ? "Fecha: Todos los días"
                          : "Fecha: ${_dateFilter!.day}/${_dateFilter!.month}/${_dateFilter!.year}",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Row(
                      children: [
                        if (_dateFilter != null)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red),
                            onPressed: () => setState(() => _dateFilter = null),
                          ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => _dateFilter = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: const Text("Elegir Día"),
                        ),
                      ],
                    )
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.db.collection('orders').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var filteredDocs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;

                  if (_userFilter.isNotEmpty) {
                    String uName = (data['userName'] ?? '').toString().toLowerCase();
                    if (!uName.contains(_userFilter)) return false;
                  }
                  if (_statusFilter != "Todos" && data['status'] != _statusFilter) return false;
                  if (_materialFilter != "Todos" && data['material'] != _materialFilter) return false;
                  if (_dateFilter != null) {
                    Timestamp? ts = data['timestamp'] as Timestamp?;
                    if (ts == null) return false;
                    DateTime oDate = ts.toDate();
                    if (oDate.year != _dateFilter!.year || oDate.month != _dateFilter!.month || oDate.day != _dateFilter!.day) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("No hay pedidos que coincidan con los filtros."),
                  ));
                }

                return ListView.builder(
                  controller: scrollController,
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var data = filteredDocs[index].data() as Map<String, dynamic>;
                    Timestamp? ts = data['timestamp'] as Timestamp?;
                    String fechaStr = "Sincronizando...";
                    if (ts != null) {
                      DateTime t = ts.toDate();
                      fechaStr = "${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
                    }

                    Color statusColor = _getStatusColor(data['status'] ?? '');

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.15),
                          child: Icon(Icons.assignment, color: statusColor),
                        ),
                        title: Text(data['material'] ?? 'Material', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Usuario: ${data['userName'] ?? 'N/A'}\nFecha/Hora: $fechaStr"),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor.withOpacity(0.3))
                          ),
                          child: Text(
                            data['status'] ?? 'Pendiente',
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 6. NUEVO: COMPONENTE DE GESTIÓN DE USUARIOS
// ==========================================
class AdminUsersSheet extends StatefulWidget {
  final FirebaseFirestore db;
  const AdminUsersSheet({super.key, required this.db});

  @override
  State<AdminUsersSheet> createState() => _AdminUsersSheetState();
}

class _AdminUsersSheetState extends State<AdminUsersSheet> {
  String _searchQuery = "";

  void _confirmarEliminacion(BuildContext context, String userId, String fullName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Eliminar cuenta de $fullName"),
        content: const Text("El usuario será eliminado de la base de datos, esto es permanente y no se puede cambiar."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Cierra el cuadro de diálogo

              try {
                // 1. Borrar usuario de la base de datos
                await widget.db.collection('users').doc(userId).delete();

                // 2. Borrar pedidos de dicho usuario
                var pedidosQuery = await widget.db.collection('orders').where('userId', isEqualTo: userId).get();
                WriteBatch loteDeBorrado = widget.db.batch();
                for (var doc in pedidosQuery.docs) {
                  loteDeBorrado.delete(doc.reference);
                }
                await loteDeBorrado.commit();

                messengerKey.currentState?.showSnackBar(SnackBar(
                  content: Text("Usuario $fullName y su historial fueron eliminados con éxito."),
                  backgroundColor: Colors.green,
                ));
              } catch (e) {
                messengerKey.currentState?.showSnackBar(SnackBar(
                  content: Text("Error al eliminar usuario: $e"),
                  backgroundColor: Colors.red,
                ));
              }
            },
            child: const Text("Eliminar", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Control de Usuarios", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Buscar usuario por nombre...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.db.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var filtrados = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String nombreCompleto = "${data['name'] ?? ''} ${data['last_name'] ?? ''}".toLowerCase();
                  return nombreCompleto.contains(_searchQuery);
                }).toList();

                if (filtrados.isEmpty) {
                  return const Center(child: Text("No se encontraron usuarios activos."));
                }

                return ListView.builder(
                  controller: scrollController,
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    var doc = filtrados[index];
                    var data = doc.data() as Map<String, dynamic>;
                    String nombreCompleto = "${data['name'] ?? 'Usuario'} ${data['last_name'] ?? ''}";
                    String rol = data['role'] ?? 'Usuario';
                    String empNo = data['employee_no'] ?? 'N/A';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(nombreCompleto, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("ID: $empNo  |  Rol: $rol"),
                        trailing: rol == "Administrador"
                            ? const Tooltip(message: "Protegido", child: Icon(Icons.shield, color: Colors.blue))
                            : IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red),
                          onPressed: () => _confirmarEliminacion(context, doc.id, nombreCompleto),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
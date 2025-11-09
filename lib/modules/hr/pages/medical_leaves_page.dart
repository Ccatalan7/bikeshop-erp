import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/hr_models.dart';
import '../services/hr_service.dart';
import '../../../shared/widgets/main_layout.dart';

class MedicalLeavesPage extends StatefulWidget {
  const MedicalLeavesPage({super.key});

  @override
  State<MedicalLeavesPage> createState() => _MedicalLeavesPageState();
}

class _MedicalLeavesPageState extends State<MedicalLeavesPage> {
  LeaveStatus? _filterStatus;
  String? _filterEmployeeId;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HRService>().loadMedicalLeaves();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Licencias Médicas',
      child: Column(
        children: [
          // Action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por empleado o diagnóstico...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.filter_list),
                  label: const Text('Filtros'),
                  onPressed: _showFilterDialog,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Licencia'),
                  onPressed: () => _showLeaveDialog(context),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Consumer<HRService>(
              builder: (context, hrService, child) {
                if (hrService.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                return FutureBuilder<List<Employee>>(
                  future: hrService.employees,
                  builder: (context, employeeSnapshot) {
                    if (!employeeSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final employees = employeeSnapshot.data!;
                    var leaves = hrService.medicalLeaves;

                    // Apply filters
                    if (_filterStatus != null) {
                      leaves = leaves.where((l) => l.status == _filterStatus).toList();
                    }
                    if (_filterEmployeeId != null) {
                      leaves = leaves.where((l) => l.employeeId == _filterEmployeeId).toList();
                    }
                    if (_searchController.text.isNotEmpty) {
                      final query = _searchController.text.toLowerCase();
                      leaves = leaves.where((l) {
                        final employee = employees.firstWhere(
                          (e) => e.id == l.employeeId,
                          orElse: () => employees.first,
                        );
                        return employee.fullName.toLowerCase().contains(query) ||
                            l.diagnosis?.toLowerCase().contains(query) == true;
                      }).toList();
                    }

                    if (leaves.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.medical_services_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No hay licencias médicas registradas',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => _showLeaveDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Registrar Licencia'),
                            ),
                          ],
                        ),
                      );
                    }

                    // Leave list
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: leaves.length,
                      itemBuilder: (context, index) {
                        final leave = leaves[index];
                        final employee = employees.firstWhere(
                          (e) => e.id == leave.employeeId,
                          orElse: () => employees.first,
                        );
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: leave.statusColor.withOpacity(0.2),
                              child: Icon(Icons.medical_services, color: leave.statusColor),
                            ),
                            title: Text(employee.fullName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(leave.leaveTypeLabel),
                                Text(
                                  '${DateFormat('dd/MM/yyyy').format(leave.startDate)} - ${DateFormat('dd/MM/yyyy').format(leave.endDate)} (${leave.daysCount} días)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (leave.diagnosis != null)
                                  Text(
                                    leave.diagnosis!,
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Chip(
                              label: Text(leave.statusLabel),
                              backgroundColor: leave.statusColor.withOpacity(0.2),
                              labelStyle: TextStyle(color: leave.statusColor),
                            ),
                            onTap: () => _showLeaveDialog(context, leave: leave),
                          ),
                        );
                      },
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

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar Licencias'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<LeaveStatus>(
              value: _filterStatus,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...LeaveStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(_getStatusLabel(status)),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _filterStatus = value;
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _filterStatus = null;
                _filterEmployeeId = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Limpiar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(LeaveStatus status) {
    switch (status) {
      case LeaveStatus.pending:
        return 'Pendiente';
      case LeaveStatus.approved:
        return 'Aprobada';
      case LeaveStatus.rejected:
        return 'Rechazada';
      case LeaveStatus.paid:
        return 'Pagada';
    }
  }

  void _showLeaveDialog(BuildContext context, {MedicalLeave? leave}) {
    final hrService = context.read<HRService>();
    final isEdit = leave != null;

    final employeeController = TextEditingController(text: leave?.employeeId ?? '');
    final startDateController = TextEditingController(
      text: leave != null ? DateFormat('dd/MM/yyyy').format(leave.startDate) : '',
    );
    final endDateController = TextEditingController(
      text: leave != null ? DateFormat('dd/MM/yyyy').format(leave.endDate) : '',
    );
    final certificateController = TextEditingController(text: leave?.certificateNumber ?? '');
    final doctorNameController = TextEditingController(text: leave?.doctorName ?? '');
    final doctorRutController = TextEditingController(text: leave?.doctorRut ?? '');
    final institutionController = TextEditingController(text: leave?.issuingInstitution ?? '');
    final diagnosisController = TextEditingController(text: leave?.diagnosis ?? '');
    final notesController = TextEditingController(text: leave?.notes ?? '');

    LeaveType selectedType = leave?.leaveType ?? LeaveType.enfermedadComun;
    LeaveStatus selectedStatus = leave?.status ?? LeaveStatus.pending;
    DateTime startDate = leave?.startDate ?? DateTime.now();
    DateTime endDate = leave?.endDate ?? DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? 'Editar Licencia Médica' : 'Nueva Licencia Médica'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Employee selector
                  FutureBuilder<List<Employee>>(
                    future: hrService.employees,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      return DropdownButtonFormField<String>(
                        value: employeeController.text.isEmpty ? null : employeeController.text,
                        decoration: const InputDecoration(labelText: 'Empleado *'),
                        items: snapshot.data!.map((employee) {
                          return DropdownMenuItem(
                            value: employee.id,
                            child: Text(employee.fullName),
                          );
                        }).toList(),
                        onChanged: (value) {
                          employeeController.text = value ?? '';
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Leave type
                  DropdownButtonFormField<LeaveType>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Tipo de Licencia *'),
                    items: LeaveType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(_getLeaveTypeLabel(type)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedType = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Dates
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: startDateController,
                          decoration: const InputDecoration(labelText: 'Fecha Inicio *'),
                          readOnly: true,
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              setState(() {
                                startDate = date;
                                startDateController.text = DateFormat('dd/MM/yyyy').format(date);
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: endDateController,
                          decoration: const InputDecoration(labelText: 'Fecha Fin *'),
                          readOnly: true,
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: startDate,
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              setState(() {
                                endDate = date;
                                endDateController.text = DateFormat('dd/MM/yyyy').format(date);
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Certificate details
                  TextFormField(
                    controller: certificateController,
                    decoration: const InputDecoration(labelText: 'Folio Licencia'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: doctorNameController,
                    decoration: const InputDecoration(labelText: 'Nombre Médico'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: doctorRutController,
                    decoration: const InputDecoration(labelText: 'RUT Médico'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: institutionController,
                    decoration: const InputDecoration(labelText: 'Institución (COMPIN/IST/Mutual)'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Status
                  DropdownButtonFormField<LeaveStatus>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: LeaveStatus.values.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(_getStatusLabel(status)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedStatus = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Diagnosis
                  TextFormField(
                    controller: diagnosisController,
                    decoration: const InputDecoration(labelText: 'Diagnóstico'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  
                  // Notes
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notas'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (isEdit)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Confirmar Eliminación'),
                      content: const Text('¿Está seguro de eliminar esta licencia médica?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true && leave.id != null) {
                    await hrService.deleteMedicalLeave(leave.id!);
                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Licencia eliminada')),
                      );
                    }
                  }
                },
                child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (employeeController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Seleccione un empleado')),
                  );
                  return;
                }

                final newLeave = MedicalLeave(
                  id: leave?.id,
                  tenantId: await hrService.tenantId,
                  employeeId: employeeController.text,
                  leaveType: selectedType,
                  startDate: startDate,
                  endDate: endDate,
                  certificateNumber: certificateController.text.isEmpty ? null : certificateController.text,
                  doctorName: doctorNameController.text.isEmpty ? null : doctorNameController.text,
                  doctorRut: doctorRutController.text.isEmpty ? null : doctorRutController.text,
                  issuingInstitution: institutionController.text.isEmpty ? null : institutionController.text,
                  status: selectedStatus,
                  diagnosis: diagnosisController.text.isEmpty ? null : diagnosisController.text,
                  notes: notesController.text.isEmpty ? null : notesController.text,
                );

                if (isEdit) {
                  await hrService.updateMedicalLeave(newLeave);
                } else {
                  await hrService.createMedicalLeave(newLeave);
                }

                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEdit ? 'Licencia actualizada' : 'Licencia creada')),
                  );
                }
              },
              child: Text(isEdit ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  String _getLeaveTypeLabel(LeaveType type) {
    switch (type) {
      case LeaveType.enfermedadComun:
        return 'Enfermedad Común';
      case LeaveType.accidenteTrabajo:
        return 'Accidente de Trabajo';
      case LeaveType.enfermedadProfesional:
        return 'Enfermedad Profesional';
      case LeaveType.maternal:
        return 'Maternal';
      case LeaveType.paternal:
        return 'Paternal';
      case LeaveType.prePostNatal:
        return 'Pre/Post Natal';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

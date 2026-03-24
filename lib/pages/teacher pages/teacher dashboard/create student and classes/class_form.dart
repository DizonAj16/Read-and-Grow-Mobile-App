import 'package:flutter/material.dart';
import 'form_field_builders.dart';

class ClassForm extends StatelessWidget {
  final TextEditingController classNameController;
  final TextEditingController classSectionController;
  final TextEditingController gradeLevelController;
  final TextEditingController schoolYearController;
  final int? selectedGradeLevel;
  final Function(int?) onGradeLevelChanged;

  const ClassForm({
    super.key,
    required this.classNameController,
    required this.classSectionController,
    required this.gradeLevelController,
    required this.schoolYearController,
    required this.selectedGradeLevel,
    required this.onGradeLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FormFieldBuilders.buildSimpleTextField(
          context: context,
          controller: classNameController,
          label: "Class Name",
          icon: Icons.edit,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Class name is required'
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: selectedGradeLevel,
          decoration: InputDecoration(
            labelText: "Grade Level",
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
          items: List.generate(5, (index) {
            final grade = index + 1;
            return DropdownMenuItem(
              value: grade,
              child: Text("Grade $grade"),
            );
          }),
          onChanged: onGradeLevelChanged,
          validator: (value) => value == null ? 'Please select a grade level' : null,
        ),
        const SizedBox(height: 16),
        FormFieldBuilders.buildSimpleTextField(
          context: context,
          controller: classSectionController,
          label: "Section",
          icon: Icons.group,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Section is required'
              : null,
        ),
        const SizedBox(height: 16),
        FormFieldBuilders.buildSimpleTextField(
          context: context,
          controller: schoolYearController,
          label: "School Year",
          icon: Icons.calendar_today,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'School year is required'
              : null,
        ),
      ],
    );
  }
}
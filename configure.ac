dnl Process this file with autoconf to produce a configure script.

# Copyright (C) 2010 Colin Watson.
#
# This file is part of binfmt-support.
#
# binfmt-support is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
#
# binfmt-support is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with binfmt-support; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301
# USA.

# Initialise and check we're in the correct directory.
AC_INIT([binfmt-support], [2.0.8], [cjwatson@debian.org])
AC_CONFIG_AUX_DIR([tools])
AM_INIT_AUTOMAKE([1.10 -Wall -Werror foreign])
AM_MAINTAINER_MODE
m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])
AC_PREREQ([2.59])
AC_CONFIG_SRCDIR([src/update-binfmts.c])
AC_GNU_SOURCE

AC_CONFIG_HEADER([config.h])
AC_CANONICAL_HOST

# Check $PATH for the following programs and append suitable options.
AC_PROG_CC
gl_EARLY
AC_PROG_CPP
CFLAGS="$CFLAGS -Wall"
if test "$GCC" = yes
then
	gl_WARN_ADD([-W])
	gl_WARN_ADD([-Wpointer-arith])
	gl_WARN_ADD([-Wwrite-strings])
	gl_WARN_ADD([-Wstrict-prototypes])
	gl_WARN_ADD([-Wshadow])
	gl_WARN_ADD([-Wformat-security])
	gl_WARN_ADD([-Wredundant-decls])
	gl_WARN_ADD([-Wno-missing-field-initializers])
fi

# Check for various header files and associated libraries.
AC_ISC_POSIX
gl_INIT

# Checks for structures and compiler characteristics.
AC_C_CONST
AC_TYPE_SIZE_T

PKG_CHECK_MODULES([libpipeline], [libpipeline])

# If we're cross-compiling, tests won't work.
AM_CONDITIONAL([CROSS_COMPILING], [test "x$cross_compiling" = xyes])

AC_CONFIG_FILES([Makefile
	gnulib/lib/Makefile
	man/Makefile
	src/Makefile
	src/tests/Makefile])
AC_OUTPUT

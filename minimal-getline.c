/*

 Copyright (C) 2011-2017 Alexis Bienvenue <paamc@passoire.fr>

 This file is part of Auto-Multiple-Choice

 Auto-Multiple-Choice is free software: you can redistribute it
 and/or modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation, either version 2 of
 the License, or (at your option) any later version.

 Auto-Multiple-Choice is distributed in the hope that it will be
 useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Auto-Multiple-Choice.  If not, see
 <http://www.gnu.org/licenses/>.

*/

/* This file contains a minimal getline implementation for use in AMC
   on platforms where getline is not included */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>

ssize_t getline(char **lineptr,size_t *n,FILE *stream) {
  ssize_t i=0;
  int c;

  if(lineptr==NULL || n==NULL || stream==NULL) {
    errno=EINVAL;
    return -1;
  }

  if (*lineptr==NULL || *n==0) {
    *n = 64;
    *lineptr=(char*)realloc(*lineptr,sizeof(char)*(*n));
    if(*lineptr==NULL) {
      return(-1);
    }
  }

  flockfile(stream);

  while((c = getc_unlocked(stream)) != EOF) {
    i++;
    if(i+1 > *n) {
      *n = *n + 16;
      *lineptr=(char*)realloc(*lineptr,sizeof(char)*(*n));

      if(*lineptr==NULL) {
        funlockfile(stream);
        return(-1);
      }
    }

    (*lineptr)[i-1]=c;
    if(c=='\n') break;
  }

  funlockfile(stream);

  (*lineptr)[i]='\0';
  return(i>0 ? i : -1);
}
